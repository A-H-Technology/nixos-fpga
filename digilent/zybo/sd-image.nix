# A flashable SD image for the Zybo: `dd` it to a microSD card, set JP5 to SD,
# and power on. Import alongside ./default.nix; build with
# config.system.build.sdImage.
{
  config,
  lib,
  modulesPath,
  ...
}: let
  cfg = config.hardware.digilent.zybo;
in {
  imports = ["${modulesPath}/installer/sd-card/sd-image.nix"];

  sdImage = {
    compressImage = lib.mkDefault false;

    # The BootROM only searches the first partition, and it must be FAT. Only
    # BOOT.BIN and u-boot.img (~1 MB together) go here; the kernel and DTB live
    # on the ext4 root so extlinux can version them per generation.
    firmwareSize = 64;
    firmwarePartitionName = "ZYBOBOOT";

    populateFirmwareCommands = ''
      cp ${cfg.uboot}/boot.bin firmware/BOOT.BIN
      cp ${cfg.uboot}/u-boot.img firmware/u-boot.img
    '';

    # sd-image.nix flags p2 bootable, which is exactly what distro_bootcmd scans
    # for extlinux.conf, so unlike boards with a stock vendor U-Boot there is no
    # boot script to stage.
    populateRootCommands = ''
      mkdir -p ./files/boot
      ${config.boot.loader.generic-extlinux-compatible.populateCmd} \
        -c ${config.system.build.toplevel} -d ./files/boot
    '';
  };
}
