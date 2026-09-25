# The U-Boot boot script that hands the stock bootloader over to NixOS.
#
# Terasic's stock script hardcodes fatload+booti, which throws away NixOS
# generations. This one fixes up the environment, optionally raises the
# HPS<->FPGA bridges, and then hands off to the extlinux.conf NixOS maintains on
# the ext4 root, so every generation stays bootable.
#
# Getting this script *run* at all takes the partition-flag trick in
# ./sd-image.nix — see the comment there.
#
# The addresses and `bridge enable` are Agilex 5 SoC facts, not DE25-Nano ones:
# the first candidates to move into common/ once a second Agilex 5 board lands.
{
  lib,
  runCommand,
  buildPackages,
  fpgaBridges,
  extraCommands,
}: let
  # U-Boot loads a boot script at ${scriptaddr} (0x81000000), so sysboot must
  # stage extlinux.conf elsewhere or it overwrites the script mid-execution.
  # DRAM is 0x80000000..0xBFFFFFFF; this clears kernel_addr_r (0x82000000) and
  # fdt_addr_r (0x86000000).
  syslinuxAddr = "0x88000000";

  # The stock U-Boot environment has no ramdisk_addr_r, and extlinux treats that
  # as fatal the moment an entry carries an INITRD line: it prints "missing
  # environment variable: ramdisk_addr_r", skips the entry, and the whole target
  # fails. NixOS always emits INITRD, and we can't drop the initrd to dodge it —
  # extlinux.conf appends `root=fstab`, so stage-1 is what knows where root is.
  #
  # `saveenv` can't persist it either: this build loads its environment from FAT
  # but saves to UBI, and there is no UBI ("Cannot find mtd partition root"), so
  # the script has to set it on every boot.
  #
  # Placed above the kernel (37 MiB at 0x82000000), the FDT, and syslinuxAddr,
  # with a ~25 MiB initrd fitting far inside the remaining 768 MiB.
  ramdiskAddr = "0x90000000";

  script = lib.concatStringsSep "\n" (
    ["setenv ramdisk_addr_r ${ramdiskAddr};"]
    # Without this the HPS<->FPGA bridges stay down and any fabric access
    # faults. Only worth skipping if the bitstream in QSPI doesn't expect them.
    ++ lib.optionals fpgaBridges [
      ''echo "de25-nano: enabling HPS<->FPGA bridges";''
      "bridge enable;"
    ]
    ++ lib.optional (extraCommands != "") extraCommands
    ++ [
      ''echo "de25-nano: handing off to extlinux on mmc 0:2";''
      "sysboot mmc 0:2 any ${syslinuxAddr} /boot/extlinux/extlinux.conf;"
    ]
  );
in
  runCommand "de25-nano-boot.scr.uimg" {
    nativeBuildInputs = [buildPackages.ubootTools];
    passAsFile = ["script"];
    inherit script;
  } ''
    mkimage -A arm64 -O linux -T script -C none -d "$scriptPath" "$out"
  ''
