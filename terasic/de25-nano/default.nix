# Terasic DE25-Nano, an Agilex 5 SoC FPGA dev board. This configures the HPS
# side: 2x Cortex-A76 + 2x Cortex-A55, ~957 MB LPDDR4, gigabit ethernet, microSD.
# The FPGA fabric sits alongside and is not managed from here.
#
# Boot chain:
#
#   QSPI (SDM reads at power-on: FPGA bitstream + U-Boot SPL + DDR/EMIF setup)
#     -> SPL loads u-boot.itb from the SD card's FAT partition
#       -> ./boot-script.nix: env fixups, `bridge enable`, then sysboot
#         -> /boot/extlinux/extlinux.conf on the ext4 root (NixOS generations)
#
# The QSPI half is deliberately untouched. Regenerating it needs Quartus Prime
# Pro (proprietary, x86-only, not in nixpkgs), and it carries the DDR controller
# config — without a valid one the ARM cores have no working RAM.
#
# Serial is the only console (115200 on ttyS0); HDMI is driven from the fabric,
# so there is no framebuffer unless an FPGA design provides one.
#
# Importing this module is enabling it, as in nixos-hardware. Pair it with
# ./sd-image.nix to build a flashable image.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.hardware.terasic.de25-nano;
in {
  options.hardware.terasic.de25-nano = {
    kernel = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./kernel {};
      defaultText = lib.literalMD "Terasic's linux-socfpga fork with the stock config";
      description = "Kernel to boot. Override the default with `.override` to change its config.";
    };

    uboot = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./uboot-stock.nix {};
      defaultText = lib.literalMD "the stock `u-boot.itb` from Terasic's SD card image";
      description = "Package whose `u-boot.itb` is placed on the FAT partition for the SPL to load.";
    };

    fpgaBridges.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Run `bridge enable` before booting, bringing up the HPS<->FPGA bridges.
        Without it any access to the fabric from Linux faults.
      '';
    };

    bootScript = {
      extraCommands = lib.mkOption {
        type = lib.types.lines;
        default = "";
        description = "U-Boot commands to run after the environment fixups, before handing off to extlinux.";
      };

      package = lib.mkOption {
        type = lib.types.package;
        readOnly = true;
        internal = true;
        default = pkgs.callPackage ./boot-script.nix {
          fpgaBridges = cfg.fpgaBridges.enable;
          inherit (cfg.bootScript) extraCommands;
        };
      };
    };
  };

  config = {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.isAarch64;
        message = "hardware.terasic.de25-nano: set nixpkgs.hostPlatform to \"aarch64-linux\".";
      }
    ];

    boot = {
      kernelPackages = pkgs.linuxPackagesFor cfg.kernel;

      loader = {
        grub.enable = false;
        generic-extlinux-compatible.enable = true;
      };

      # Matches the DTB's stdout-path. No framebuffer exists on this board.
      kernelParams = ["console=ttyS0,115200"];
      consoleLogLevel = lib.mkDefault 7;
    };

    # NixOS builds its initrd for a general-purpose machine: sd-image.nix switches
    # on hardware.enableAllHardware and kernel.nix adds its own defaults, which
    # together ask for ~110 modules (3w-9xxx, pata_*, hid_*, ext2, tpm-crb).
    # makeModulesClosure runs with allowMissing = false, so every one Terasic's
    # config doesn't build is a hard build failure. This is fixed hardware and
    # the whole root path (Cadence SDHCI, ext4) is =y, so the honest initrd
    # module set is empty. Dropping all-hardware also drops
    # enableRedistributableFirmware, keeping linux-firmware off a 957 MB board.
    hardware.enableAllHardware = lib.mkForce false;
    boot.initrd = {
      includeDefaultModules = false;
      availableKernelModules = lib.mkForce [];
    };

    hardware.deviceTree = {
      enable = true;
      name = "intel/socfpga_agilex5_de25_nano.dtb";
      package = lib.mkDefault "${config.boot.kernelPackages.kernel}/dtbs";
    };

    # Terasic's config has `# CONFIG_NF_TABLES is not set`, so the default
    # iptables-nft can only fail with "Failed to initialize nft: Protocol not
    # supported". The legacy xtables backend is built (CONFIG_IP_NF_IPTABLES=m),
    # so use it instead of shipping a firewall that cannot start.
    networking.firewall.package = lib.mkDefault pkgs.iptables-legacy;
  };
}
