# Digilent Zybo (the original, 2014 — not the Zybo Z7), a Zynq-7010 board. This
# configures the PS side: 2x Cortex-A9 at 650 MHz, 512 MB DDR3, gigabit ethernet,
# microSD. The PL fabric is left unconfigured.
#
# Boot chain, all of it built from mainline source:
#
#   BootROM reads BOOT.BIN off the card's first (FAT) partition
#     -> U-Boot SPL: ps7_init (DDR, MIO, clocks), loads u-boot.img from FAT
#       -> U-Boot distro_bootcmd finds the bootable ext4 root
#         -> /boot/extlinux/extlinux.conf (NixOS generations)
#
# The board's mode jumper (JP5) has to be on SD for the BootROM to look there.
#
# Importing this module is enabling it, as in nixos-hardware. Pair it with
# ./sd-image.nix to build a flashable image.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.hardware.digilent.zybo;
in {
  options.hardware.digilent.zybo = {
    uboot = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./uboot.nix {};
      defaultText = lib.literalMD "mainline U-Boot, `xilinx_zynq_virt_defconfig` for `zynq-zybo`";
      description = "Package with `boot.bin` (the SPL, written as BOOT.BIN) and `u-boot.img` at its root.";
    };
  };

  config = {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.isAarch32;
        message = "hardware.digilent.zybo: set nixpkgs.hostPlatform to \"armv7l-linux\".";
      }
    ];

    boot = {
      loader = {
        grub.enable = false;
        generic-extlinux-compatible.enable = true;
      };

      # The DT aliases uart1 (the one wired to the FT2232) as serial0, which the
      # Cadence driver names ttyPS0.
      kernelParams = ["console=ttyPS0,115200"];
    };

    # sd-image.nix switches this on for unknown machines, and with it
    # enableRedistributableFirmware: linux-firmware on a board with no wifi and
    # no GPU. This is fixed hardware whose whole root path (Arasan SDHCI, ext4)
    # is =y in multi_v7_defconfig, so it boots without any of that.
    hardware.enableAllHardware = lib.mkForce false;

    # nixos-generate-config bakes in bcachefs-tools, and 1.39.7 doesn't compile
    # with a 32-bit time_t: https://github.com/koverstreet/bcachefs-tools/issues/1087
    # Remove once nixpkgs ships a release with "fusemount: build on targets with
    # a 32 bit time_t". The board's config is written elsewhere and deployed, so
    # nothing on it needs the generator anyway.
    system.tools.nixos-generate-config.enable = lib.mkDefault false;

    # Setting a name makes extlinux.conf carry an explicit FDT line. Zynq's U-Boot
    # environment has no fdtfile, so FDTDIR alone would go looking for a DTB
    # named after the SoC and board that doesn't exist. No xilinx/ prefix: 32-bit
    # ARM selects ARCH_WANT_FLAT_DTB_INSTALL, so the kernel's dtbs output is flat
    # even though the sources live under arch/arm/boot/dts/xilinx/.
    hardware.deviceTree = {
      enable = true;
      name = "zynq-zybo.dtb";
    };
  };
}
