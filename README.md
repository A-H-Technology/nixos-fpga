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

Each board has a README covering how to use it, its console, boot chain and
known limits.

## Binary cache

CI builds every board's kernel and example image on native ARM runners and
pushes them to cachix. Add the cache, or every vendor kernel gets built from
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
- More boards (Zynq / Kria, other Agilex and Cyclone SoC kits).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).
