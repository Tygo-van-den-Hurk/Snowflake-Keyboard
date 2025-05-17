{
  description = "The flake that is used add Node and a couple of other programs to the shell.";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    flake-utils.url = "github:numtide/flake-utils";

    pre-commit-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs = {
        flake-compat.follows = "flake-compat";
        nixpkgs.follows = "nixpkgs";
      };
    };

    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
      };
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      flake-utils,
      treefmt-nix,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let

        pkgs = import nixpkgs { inherit system; };
        treefmtEval = treefmt-nix.lib.evalModule pkgs ./.config/treefmt.nix;
        pre-commit-check = inputs.pre-commit-hooks.lib.${system}.run (import ./.config/pre-commit.nix);
        inherit (pkgs) lib;

      in
      rec {
        # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ Nix Flake Check ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ #

        checks = packages // {
          formatting = treefmtEval.config.build.check self;
          inherit pre-commit-check;
        };

        # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ Nix Fmt ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ #

        formatter = treefmtEval.config.build.wrapper;

        # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ Nix Run ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ #

        apps = {

          ergogen = {
            type = "app";
            program = builtins.toString (
              pkgs.writeShellScript "ergogen" ''
                set -e

                root="$(git rev-parse --show-toplevel)/hardware"

                src="$HOME/pcbs/src"
                [ -d $src ] && mkdir --parents $src

                out="$HOME/pcbs/output"
                [ -d $out ] && mkdir --parents $out

                ${packages.ergogen}/bin/ergogen --debug --clean $src --output $out
              ''
            );
          };

          pcb = {
            type = "app";
            program = builtins.toString (
              pkgs.writeShellScript "update-pcb" ''
                set -e
                nix run .#ergogen
                root="$(git rev-parse --show-toplevel)/hardware"
                cp $HOME/pcbs/output/pcbs/* $HOME/pcbs/kicad/
              ''
            );
          };

          watch-ergogen = {
            type = "app";
            program = builtins.toString (
              pkgs.writeShellScript "watch-ergogen" ''
                set -e
                ${pkgs.nodemon}/bin/nodemon \
                  --exec "nix run .#ergogen" \
                  --watch "./hardware/src/**/*.*"
              ''
            );
          };

          watch-pcb = {
            type = "app";
            program = builtins.toString (
              pkgs.writeShellScript "watch-ergogen" ''
                set -e
                ${pkgs.nodemon}/bin/nodemon \
                  --exec "nix run .#update-pcb" \
                  --watch "./hardware/src/**/*.*"
              ''
            );
          };
        };

        # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ Nix Develop ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ #

        devShells.default = pkgs.mkShell {
          inherit (pre-commit-check) shellHook;
          nativeBuildInputs =
            pre-commit-check.enabledPackages # the packages for running/testing pre-commit hooks
            ++ (with packages; [
              ergogen # generate the files from the config
              openjscad # generate the STL files from JScad files.
              freerouting # autoroute PCBs so that you don't have to to it yourself
            ])
            ++ (with pkgs; [
              act # Run / check GitHub Actions locally.
              git # Pull, commit, and push changes.
              kicad # View and wire the PCBs.
            ]);
        };

        # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ Nix Build ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ #

        packages = rec {

          default = pkgs.stdenv.mkDerivation rec {
            name = "pcb";
            src = ./.;
            installPhase = ''
              runHook preInstall

              mkdir --parents $out
              cp --recursive ${hardware} $out/hardware
              cp --recursive ${software} $out/software

              runHook postInstall
            '';
          };

          #| ---------------------------------------------- Software ----------------------------------------------- |#

          software = pkgs.stdenv.mkDerivation rec {
            name = "pcb";
            src = ./software;

            buildPhase = ''
              runHook preBuild

              # ...

              runHook postBuild
            '';

            installPhase = ''
              runHook preInstall

              mkdir --parents $out

              runHook postInstall
            '';
          };

          #| ---------------------------------------------- Hardware ----------------------------------------------- |#

          # all the hardware files, excluding post processing
          hardware-raw = pkgs.stdenv.mkDerivation rec {
            name = "pcb";
            src = ./hardware/src;

            buildPhase = ''
              runHook preBuild

              ${ergogen}/bin/ergogen --clean --output output --debug .

              runHook postBuild
            '';

            installPhase = ''
              runHook preInstall

              mkdir --parents $out
              cp --recursive output/* $out

              runHook postInstall
            '';
          };

          # all the hardware files, including post processing
          hardware = pkgs.stdenv.mkDerivation rec {
            name = "pcb";
            src = ./hardware/src;
            installPhase = ''
              runHook preInstall

              mkdir --parents $out/cases
              cp --recursive ${cases}/* $out/cases

              mkdir --parents $out/pcbs
              cp --recursive ${pcbs}/* $out/pcbs

              mkdir --parents $out/outlines
              cp --recursive ${outlines}/* $out/outlines

              mkdir --parents $out/points
              cp --recursive ${points}/* $out/points

              runHook postInstall
            '';
          };

          pcbs = pkgs.stdenv.mkDerivation rec {
            name = "pcb";
            src = ./hardware/src;

            buildPhase = ''
              runHook preBuild

              # Patches kicad CLI as it requires a home dir
              HOME="$(pwd)"

              mkdir --parents $HOME/pcbs/not-routed/kicad/
              cp --recursive ${hardware-raw}/pcbs/* $HOME/pcbs/not-routed/kicad/
              for pcb in $HOME/pcbs/not-routed/kicad/*; do
                if [ -f "$pcb" ]; then

                  name=$(basename "$pcb" | sed 's/\..*//')

                  echo "> trying to convert: $pcb into an DSN file..."
                  mkdir --parents $HOME/pcbs/not-routed/dns
                  # ${pkgs.kicad}/bin/kicad-cli pcb export dsn "$pcb" \
                  #   --output $HOME/pcbs/not-routed/dns/$name.dns

                  echo "> trying to wire $pcb automatically..."
                  mkdir --parents $HOME/pcbs/pre-routed/ses
                  mkdir --parents $HOME/pcbs/pre-routed/dns
                  # ${freerouting}/bin/freerouting -c \
                  #   -de "$HOME/pcbs/not-routed/dns/$name.dns" \
                  #   -do "$HOME/pcbs/pre-routed/ses/$name.ses" \
                  #   -bo "$HOME/pcbs/pre-routed/dns/$name.dns"

                  echo "> converting it back into a kicad PCB..."
                  mkdir --parents $HOME/pcbs/pre-routed/kicad
                  # TODO: implement

                  # Seeing if the kicad PCB was produced successfully...
                  if [ -f $HOME/pcbs/pre-routed/kicad/$name.kicad_pcb ]; then
                    pcb="$HOME/pcbs/pre-routed/kicad/$name.kicad_pcb"
                  fi

                  echo "> trying to create PNG images of $pcb..."
                  mkdir --parents $HOME/pcbs/images/png
                  ${pkgs.kicad}/bin/kicad-cli pcb render $pcb \
                    --output $HOME/pcbs/images/png/$name.png \
                    --quality high

                  echo "> trying to create SVG images of $pcb..."
                  mkdir --parents $HOME/pcbs/images/svg
                  ${pkgs.kicad}/bin/kicad-cli pcb export svg $pcb \
                    --layers F.Cu,B.Cu,F.SilkS,F.Mask,B.Mask,Edge.Cuts \
                    --exclude-drawing-sheet --fit-page-to-board \
                    --output $HOME/pcbs/images/svg/$name.svg

                else
                  echo "$pcb is not a file, skipping..."
                fi
              done

              runHook postBuild
            '';

            installPhase = ''
              runHook preInstall

              mkdir --parents $out
              cp --recursive $HOME/pcbs/* $out

              runHook postInstall
            '';
          };

          outlines = pkgs.stdenv.mkDerivation rec {
            name = "pcb";
            src = ./hardware/src;
            installPhase = ''
              runHook preInstall

              mkdir --parents $out
              cp --recursive ${hardware-raw}/outlines/* $out

              runHook postInstall
            '';
          };

          points = pkgs.stdenv.mkDerivation rec {
            name = "pcb";
            src = ./hardware/src;
            installPhase = ''
              runHook preInstall

              mkdir --parents $out
              cp --recursive ${hardware-raw}/points/* $out

              runHook postInstall
            '';
          };

          cases = pkgs.stdenv.mkDerivation rec {
            name = "pcb";
            src = ./hardware/src;

            buildPhase = ''
              runHook preBuild

              mkdir --parents ./cases
              cp --recursive ${hardware-raw}/cases/* cases/
              for file in ./cases/*; do
                if [ -f "$file" ]; then
                  echo "trying to convert: $file into an STL file..."
                  ${openjscad}/bin/openjscad $file -of stl
                else
                  echo "$file is not a file, skipping..."
                fi
              done

              runHook postBuild
            '';

            installPhase = ''
              runHook preInstall

              mkdir --parents $out
              cp --recursive cases/* $out

              runHook postInstall
            '';
          };

          #| --------------------------------------------- Dependencies -------------------------------------------- |#

          # for reading the config and generating the files.
          ergogen = pkgs.buildNpmPackage {
            pname = "ergogen";
            version = "4.0.2";

            forceGitDeps = true;

            src = pkgs.fetchFromGitHub {
              owner = "ergogen";
              repo = "ergogen";
              tag = "v4.0.2";
              hash = "sha256-RP+mDjL6M+gHFrQvFd7iZaL2aQXk+6gQEUf0tWaTp3g=";
            };

            npmDepsHash = "sha256-zsC8QcrEy9Ie7xaad/pk5D6wL8NgMdgfymAiGy8vnsY=";

            makeCacheWritable = true;
            dontNpmBuild = true;
            npmPackFlags = [ "--ignore-scripts" ];
            NODE_OPTIONS = "--openssl-legacy-provider";

            doInstallCheck = true;
            nativeInstallCheckInputs = [ pkgs.versionCheckHook ];

            passthru.updateScript = pkgs.nix-update-script { };

            meta = {
              description = "Ergonomic keyboard layout generator.";
              homepage = "https://ergogen.xyz";
              mainProgram = "ergogen";
              license = lib.licenses.mit;
            };
          };

          # for converting JS CAD files to STL
          openjscad = pkgs.stdenv.mkDerivation rec {
            pname = "openjscad";
            version = "1.6.1";

            src = pkgs.fetchFromGitHub {
              owner = "legacy-Tygo-van-den-Hurk/";
              repo = "openjscad-cli-v${version}";
              tag = "v${version}";
              hash = "sha256-UPdyA1Bm6CEoh1KxDkaMyyBbDuC/vrBGzp7rIpGZ7pA=";
            };

            nativeBuildInputs = [ pkgs.makeWrapper ];

            installPhase = ''
              runHook preInstall

              mkdir --parents $out/bin
              makeWrapper ${pkgs.nodejs}/bin/node $out/bin/openjscad \
                --add-flags "${src}/node_modules/.bin/openjscad"

              runHook postInstall
            '';
          };

          # Auto routes PCBs for you
          freerouting = pkgs.stdenv.mkDerivation rec {
            pname = "freerouting";
            version = "2.1.0";

            nativeBuildInputs = [ pkgs.makeWrapper ];

            src = pkgs.fetchurl {
              url = "https://github.com/${pname}/${pname}/releases/download/v${version}/${pname}-${version}.jar";
              sha256 = "sha256-LAfVj3XawDeCZkCB56WLQcJUANhxqfzxZqLqb+YNXe8=";
            };

            unpackPhase = ''
              runHook preUnpack
              echo "nothing to do..."
              runHook postUnpack
            '';

            installPhase = ''
              runHook preInstall

              mkdir --parents $out/lib
              cp $src $out/lib/${pname}-${version}.jar

              mkdir --parents $out/bin
              makeWrapper ${pkgs.zulu23}/bin/java $out/bin/freerouting \
                --add-flags "-jar $out/lib/${pname}-${version}.jar"

              runHook postInstall
            '';
          };
        };

        # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ #
      }
    );
}
