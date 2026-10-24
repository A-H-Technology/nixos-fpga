# Digilent Zybo

The original Zybo (2014), a Zynq-7010 board. Not the Zybo Z7: that one has a
different DDR setup, so this image won't bring up its RAM. The original has a
VGA port and just says "ZYBO" on the silkscreen. This module covers the PS
(ARM) side:

- 2x Cortex-A9 at 650 MHz (32-bit, `armv7l-linux`)
- 512 MB DDR3
- gigabit ethernet
- microSD

The PL fabric is loaded from Linux, through [common/fpga](../../common/fpga):
`/dev/fpga-load` by hand, or `hardware.fpga.bitstream` at every boot.

## Use it

```nix
{
  inputs.nixos-fpga.url = "github:A-H-Technology/nixos-fpga";

  outputs = { nixpkgs, nixos-fpga, ... }: {
    nixosConfigurations.my-board = nixpkgs.lib.nixosSystem {
      modules = [
        nixos-fpga.nixosModules.digilent-zybo
        nixos-fpga.nixosModules.digilent-zybo-sd-image # omit if you lay out the card yourself
        {
          nixpkgs.hostPlatform = "armv7l-linux";
          nixpkgs.buildPlatform = "x86_64-linux";
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
nix build github:A-H-Technology/nixos-fpga#sd-image-digilent-zybo
sudo dd if=result of=/dev/sdX bs=4M conv=fsync status=progress
```

Set the mode jumper JP5 to **SD** before powering on.

Cross-compile from x86_64 as shown. Hydra caches nothing for armv7l, so a
native or emulated armv7l build compiles the entire system from source.
Cross-building does too, the first time. Add the
[binary cache](../../README.md#binary-cache) and keep `buildPlatform =
"x86_64-linux"` to get CI's builds, because only cross-built store paths match
the cache. The board has 512 MB of RAM, so don't build on it. Deploy closures
to it from elsewhere, and set `nix.settings.max-jobs = 1` in its config.

## Console

The micro-USB port labelled PROG/UART is an FT2232: channel A is JTAG, and
channel B is the serial console, `ttyPS0` at 115200 8N1. It shows up as the
second `ttyUSB` device. The HDMI and VGA ports are wired to the fabric, so
there is no display unless your FPGA design provides one.

## Boot chain

```
BootROM reads BOOT.BIN from the card's first (FAT) partition
  -> U-Boot SPL: ps7_init (DDR, MIO, clocks), loads u-boot.img       <- mainline, from source
    -> U-Boot distro_bootcmd finds the bootable ext4 partition       <- mainline, from source
      -> /boot/extlinux/extlinux.conf on the ext4 root               <- NixOS generations
```

There are no vendor blobs, and nothing comes from Vivado. U-Boot ships the
Zybo's `ps7_init_gpl.c` in-tree, and the kernel and DTB (`zynq-zybo.dtb`)
are nixpkgs' mainline LTS. Every generation is bootable from the extlinux
menu, so rollback works as on any NixOS machine.

## Options

All options live under `hardware.digilent.zybo`:

| Option | Default | What it's for |
|--------|---------|---------------|
| `uboot` | mainline, `xilinx_zynq_virt_defconfig` with `zynq-zybo` | Any package with `boot.bin` and `u-boot.img` at its root. |

The kernel is NixOS's usual `boot.kernelPackages`, so set that directly to
change it.

The fabric's options are `hardware.fpga.*` ([common/fpga](../../common/fpga)).
This module sets the manager (the devcfg block, driver `zynq-fpga`, which
nixpkgs' kernel builds as a module). Set `hardware.fpga.bitstream` to load a
design at boot.

## Loading the fabric

The Zynq driver takes a `.bit`'s payload with every 32-bit word byte-swapped.
[chipsmith](https://github.com/A-H-Technology/chipsmith) writes that format
as `build/<name>.bin` and loads it over ssh with `chipsmith flash --ssh HOST`;
the ssh user needs to be in the `fpga` group.

A design must drive the PS7's `IRQF2P[19:16]` low. Those are the ARM cores'
FIQ and IRQ, straight from the fabric and active high, and an interconnect
input nothing drives reads as 1. A PL-only design that doesn't instantiate a
PS7 (Vivado's included) therefore holds FIQ on both cores, and once the load
turns the PL->PS level shifters on, Linux hangs with both cores in the FIQ
handler. chipsmith ties them off in every design. U-Boot enables the same
level shifters, so the hang also hits a board booting with such a design
already loaded over JTAG.

## Known limits

- **Kernel and U-Boot follow nixpkgs.** Unlike a vendor-forked board, a nixpkgs
  bump moves both, and the update workflow doesn't label that
  `needs-hardware-test`. That's the same bet nixos-hardware makes for
  upstreamed boards.
- **Bitstreams only.** A design that adds devices to the PS (AXI
  peripherals, PL interrupts) needs a device-tree overlay too, which
  `common/fpga` doesn't do yet.
