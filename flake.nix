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

                src="$root/src"
                [ -d $src ] && mkdir --parents $src

                out="$root/output"
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
                cp $root/output/pcbs/* $root/kicad/
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
              jscad # generate the STL files from JScad files.
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

          hardware = pkgs.stdenv.mkDerivation rec {
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

          pcbs = pkgs.stdenv.mkDerivation rec {
            name = "pcb";
            src = ./hardware/src;
            installPhase = ''
              runHook preInstall

              mkdir --parents $out
              cp --recursive ${hardware}/pcbs/* $out

              runHook postInstall
            '';
          };

          outlines = pkgs.stdenv.mkDerivation rec {
            name = "pcb";
            src = ./hardware/src;
            installPhase = ''
              runHook preInstall

              mkdir --parents $out
              cp --recursive ${hardware}/outlines/* $out

              runHook postInstall
            '';
          };

          points = pkgs.stdenv.mkDerivation rec {
            name = "pcb";
            src = ./hardware/src;
            installPhase = ''
              runHook preInstall

              mkdir --parents $out
              cp --recursive ${hardware}/points/* $out

              runHook postInstall
            '';
          };

          cases = pkgs.stdenv.mkDerivation rec {
            name = "pcb";
            src = ./hardware/src;

            buildPhase = ''
              runHook preBuild

              # cp --recursive ${hardware}/cases/* .

              # echo ""

              # cat cases/production.jscad

              # echo ""

              # ${jscad}/bin/jscad cases/production.jscad -o cases/production.stl

              runHook postBuild
            '';

            installPhase = ''
              runHook preInstall

              mkdir --parents $out
              cp --recursive ${hardware}/cases/* $out

              runHook postInstall
            '';
          };

          #| --------------------------------------------- Dependencies -------------------------------------------- |#

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

          jscad =
            let

              main-repo = pkgs.fetchFromGitHub {
                owner = "legacy-Tygo-van-den-Hurk/";
                repo = "OpenJSCAD.org";
                tag = "@jscad/cli@2.3.5+lockfile";
                hash = "sha256-hWXtHh4MKxM0X2d9JCq2IDKjAWl5IuzbrhU6XGeepSI=";
              };

            in
            pkgs.buildNpmPackage {
              pname = "jscad";
              version = "2.3.5";

              forceGitDeps = true;

              src = "${main-repo}/packages/cli";
              npmDepsHash = "sha256-EE9u/eauhrERi/SmjN87Xkk5C/xW8xR+GHUPdEp/s7c=";

              makeCacheWritable = true;
              dontNpmBuild = true;
              dontNpmPrune = true;

              npmPackFlags = [ "--ignore-scripts" ];
              NODE_OPTIONS = "--openssl-legacy-provider";

              doInstallCheck = true;

              passthru.updateScript = pkgs.nix-update-script { };

              meta = {
                homepage = "https://openjscad.xyz/";
                mainProgram = "jscad";
                license = lib.licenses.mit;
                description = ''
                  JSCAD is a set of modular, browser and command line tools for creating parametric 2D and 3D designs
                  with JavaScript code.
                '';
              };
            };
        };

        # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ #
      }
    );
}
