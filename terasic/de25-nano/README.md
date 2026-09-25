# Terasic DE25-Nano

An Agilex 5 SoC FPGA dev board. This module covers the HPS (ARM) side:

- 2x Cortex-A76 + 2x Cortex-A55
- ~957 MB LPDDR4
- gigabit ethernet
- microSD

The FPGA fabric is left alone. Whatever bitstream is in QSPI keeps running.

## Use it

```nix
{
  inputs.nixos-fpga.url = "github:A-H-Technology/nixos-fpga";

  outputs = { nixpkgs, nixos-fpga, ... }: {
    nixosConfigurations.my-board = nixpkgs.lib.nixosSystem {
      modules = [
        nixos-fpga.nixosModules.terasic-de25-nano
        nixos-fpga.nixosModules.terasic-de25-nano-sd-image # omit if you lay out the card yourself
        {
          nixpkgs.hostPlatform = "aarch64-linux";
          # ...your config
        }
      ];
    };
  };
}
```

Build the image with `nix build .#nixosConfigurations.my-board.config.system.build.sdImage`.
Or grab the example image, which autologins `nixos` on serial:

```sh
nix build github:A-H-Technology/nixos-fpga#sd-image-terasic-de25-nano
sudo dd if=result of=/dev/sdX bs=4M conv=fsync status=progress
```

Build on an aarch64 machine or on x86 with
`boot.binfmt.emulatedSystems = ["aarch64-linux"]`, and add the
[binary cache](../../README.md#binary-cache) so the kernel isn't compiled
locally. The board has 957 MB of RAM, so don't build on it. Deploy closures to
it from elsewhere, and set `nix.settings.max-jobs = 1` in its config.

## Console

Serial only, `ttyS0` at 115200 8N1. HDMI is driven from the fabric, so there's
no display unless your FPGA design provides one.

A good boot shows these lines on serial, then extlinux's menu:

```
de25-nano: enabling HPS<->FPGA bridges
de25-nano: handing off to extlinux on mmc 0:2
```

## Boot chain

```
QSPI (read by the SDM at power-on: bitstream + U-Boot SPL + DDR/EMIF setup)  <- untouched
  -> SPL loads u-boot.itb from the card's FAT partition                     <- stock blob
    -> boot.scr.uimg: sets ramdisk_addr_r, `bridge enable`, sysboot          <- generated
      -> /boot/extlinux/extlinux.conf on the ext4 root                       <- NixOS generations
```

Every generation is bootable from the extlinux menu, so rollback works as on
any NixOS machine. The comments in `boot-script.nix` and `sd-image.nix` explain
each workaround.

## Options

All options live under `hardware.terasic.de25-nano`:

| Option | Default | What it's for |
|--------|---------|---------------|
| `kernel` | Terasic's `linux-socfpga` fork, stock config | Use `.override`/`.overrideAttrs` to change it. A different kernel means building it yourself. |
| `uboot` | stock `u-boot.itb` ([provenance](PROVENANCE.md)) | Any package with a `u-boot.itb` at its root. |
| `fpgaBridges.enable` | `true` | Runs `bridge enable` in U-Boot. Without it, Linux faults on any fabric access. |
| `bootScript.extraCommands` | `""` | U-Boot commands run just before extlinux. |

## Known limits

- **No nftables.** Terasic's config doesn't build it, so the module switches
  the NixOS firewall to the iptables-legacy backend. `networking.nftables.enable`
  won't work without a custom kernel config.
- **Vendor kernel only.** The board's DTB exists only in Terasic's fork. The
  kernel tracks Terasic's `de25-nano-6.12.11-lts` branch, and new kernel base
  branches are adopted by hand after a hardware test.
- **Stock U-Boot.** See [PROVENANCE.md](PROVENANCE.md).
