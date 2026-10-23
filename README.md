# nixos-fpga

NixOS hardware support for FPGA and SoC-FPGA boards, in the spirit of
[nixos-hardware](https://github.com/NixOS/nixos-hardware).

These boards need things nixos-hardware doesn't handle:
- **Vendor kernel forks** that Hydra never builds. This repo builds them in CI and serves them from its own binary cache.
- **Vendored boot blobs**, each with documented provenance.
- **SD-card boot chains**, which have to hand a vendor bootloader over to NixOS generations.

## Boards

| Board | SoC | Module | Status |
|-------|-----|--------|--------|
| [Terasic DE25-Nano](terasic/de25-nano) | Intel Agilex 5 | `terasic-de25-nano` | HPS boots NixOS. The fabric isn't managed yet. |
| [Digilent Zybo](digilent/zybo) (original, not Z7) | AMD Zynq-7010 | `digilent-zybo` | PS side, cross-built from x86_64. Not yet booted on hardware. |

Each board has a README covering how to use it, its console, boot chain and
known limits.

## Binary cache

CI builds every board's kernel and example image and pushes them to cachix.
aarch64 boards build on native ARM runners. 32-bit boards are cross-built on
x86_64, so their cache hits need `nixpkgs.buildPlatform = "x86_64-linux"`. Add the cache, or every vendor kernel gets built from
source on your machine:

```nix
nix.settings = {
  substituters = ["https://nixos-fpga.cachix.org"];
  trusted-public-keys = ["nixos-fpga.cachix.org-1:CACHIX_PUBLIC_KEY"];
};
```

## How updates work

A daily job bumps nixpkgs and runs every package's `updateScript`
(`nix run .#update`). It opens a PR, and CI builds and caches it.

- PRs that only move nixpkgs **merge themselves** once green.
- PRs that move a kernel get the **`needs-hardware-test`** label and wait for
  someone to flash and boot a board. CI can prove a kernel builds, but it can't
  prove the board boots.

## Roadmap

- **`common/fpga/`:** a vendor-neutral `hardware.fpga` layer for loading
  bitstreams at boot through fpga-manager and device-tree overlays, with the
  DE25-Nano as the first implementation.
- U-Boot built from source for the DE25-Nano.
- The mainline kernel once the DE25-Nano DTB is upstreamed.
- More boards (Kria, the Zybo Z7, other Agilex and Cyclone SoC kits).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).
