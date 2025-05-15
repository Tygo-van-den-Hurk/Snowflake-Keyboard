> This submodule is for generating the hardware of my keyboard.

[< Back to the main README](../README.md)

# Hardware

- [Hardware](#hardware)
  - [Overview](#overview)
  - [Ergogen](#ergogen)
    - [Nix Run](#nix-run)
    - [Nix build](#nix-build)
    - [Adding custom footprints](#adding-custom-footprints)
  - [External Resources](#external-resources)
  - [Components](#components)

## Overview

For the generating the files we need for the hardware we'll be using [ergogen](https://github.com/ergogen/ergogen). [Ergogen](https://github.com/ergogen/ergogen) is a program that allows you to build keyboards from a YAML config file.

## Ergogen

We use ergogen to build the PCBs, outlines, cases, and points for us. There are two ways to get the output of our config:

- nix run
- nix build

The difference is that `nix run` is in place while `nix build` creates a derivation and doesn't change the repo at all.

### Nix Run

To update the output folder without running the entire derivation:

```sh
nix run .#ergogen
```

There is also a way to watch the config file and the footprints using:

```sh
nix run .#watch-ergogen
```

If you're already past the prototyping stage and want to wire the PCB you can run:

```sh
nix run .#pcb
nix run .#watch-pcb
```

This will run ergogen and then copy the pcb output to the kicad folder, this way you can open kicad in the kicad folder and reopen the PCB every time you change to config to find an up to date version freshly generated.

### Nix build

To build any of it use:

```SH
nix build .#pcbs
nix build .#outlines
nix build .#cases
nix build .#points

# For all of them:
nix build .#hardware
```

to build any of them. You can also get in a dev shell with ergogen using `nix develop` and then run ergogen manually.

### Adding custom footprints

There is just one problem: Ergogen does not natively support the pro micro I want to use for my keyboard. So to solve this we have to use footprints. Footprints is a way to extend ergogen's functionality beyond it's native capabilities.

To use footprints we have to use the following structure: there has to be a directory called `footprints` and a file called `config.yaml`. The `config.yaml` is where we'll describe our keyboard to ergogen, and in the `footprints` folder we'll put our missing footprints. Thanks to [@Narkoleptika](https://github.com/Narkoleptika)'s hard work (or who ever he got it from) there is a footprint for the pro micro.

If you need any footprint that this repository is missing, you can find it's JavaScript file, and add it to the `./src/footprints/` directory. There are a lot of footprints you can use. Just make sure it's well tested, because a bad footprint could technically destroy your microcontroller.

## External Resources

- [The ergogen docs](https://docs.ergogen.xyz/) for any questions about how ergogen works.
- [Web-based deployments](https://ergogen.ceoloide.com/) for getting a visual impression of what the keys look like.
- [The ergogen v4 guid I used](https://flatfootfox.com/ergogen-introduction/) for a step by step tutorial.
- [A website that converts JS CAD to STL](https://neorama.de/). This is nice as a JS CAD file isn't useful on its own.

## Components

Here are the components I used for my keyboard:

- Choc key switches
- a `pro micro` micro controller
- my self made PCB
