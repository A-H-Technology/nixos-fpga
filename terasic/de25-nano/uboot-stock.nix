# U-Boot proper (plus ATF BL31), byte-for-byte from Terasic's stock SD card
# image — see ./PROVENANCE.md. This is what the SPL in QSPI expects to load,
# and the stock build already has sysboot/extlinux/distro_bootcmd compiled in,
# so NixOS needs no bootloader rebuild at all.
#
# Rebuildable from terasic/u-boot-socfpga + arm-trusted-firmware, but a mismatch
# with the SPL in QSPI leaves the board unbootable until the card is reflashed,
# so a from-source build has to be proven on hardware before it can be default.
{
  lib,
  runCommand,
}:
runCommand "u-boot-de25-nano-stock" {
  meta = {
    description = "Stock U-Boot FIT image for the Terasic DE25-Nano";
    license = lib.licenses.gpl2Plus;
    sourceProvenance = [lib.sourceTypes.binaryFirmware];
    platforms = ["aarch64-linux"];
  };
} ''
  install -Dm644 ${./firmware}/u-boot.itb "$out/u-boot.itb"
''
