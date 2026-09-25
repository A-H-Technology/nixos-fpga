# A flashable SD image for the DE25-Nano: `dd` it to a microSD card and boot.
# Import alongside ./default.nix; build with config.system.build.sdImage.
{
  config,
  lib,
  modulesPath,
  ...
}: let
  cfg = config.hardware.terasic.de25-nano;
in {
  imports = ["${modulesPath}/installer/sd-card/sd-image.nix"];

  sdImage = {
    compressImage = lib.mkDefault false;

    # Only u-boot.itb (~1 MB) and boot.scr.uimg go here; the kernel and DTB live
    # on the ext4 root so extlinux can version them per generation.
    firmwareSize = 64;
    firmwarePartitionName = "DE25BOOT";

    populateFirmwareCommands = ''
      cp ${cfg.uboot}/u-boot.itb firmware/u-boot.itb
      cp ${cfg.bootScript.package} firmware/boot.scr.uimg
    '';

    populateRootCommands = ''
      mkdir -p ./files/boot
      ${config.boot.loader.generic-extlinux-compatible.populateCmd} \
        -c ${config.system.build.toplevel} -d ./files/boot
    '';

    # distro_bootcmd narrows its scan to bootable partitions first
    # (`part list mmc 0 -bootable devplist`), and sd-image.nix hardcodes the flag
    # onto p2 alone — so devplist comes back "2" and boot.scr.uimg on the FAT
    # partition is unreachable. Flag p1 too, so it is scanned first and the boot
    # script gets to set ramdisk_addr_r and enable the bridges.
    #
    # p2 deliberately keeps its flag as a fallback path, even though today that
    # path is exactly the one that dies on the missing ramdisk_addr_r.
    #
    # An MBR boot flag is just 0x80 in the partition entry and nothing here
    # consumes it but U-Boot's distro script — the SPL in QSPI is what actually
    # starts this board.
    postBuildCommands = ''
      sfdisk --activate $img 1 2
    '';
  };
}
