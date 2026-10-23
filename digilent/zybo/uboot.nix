# Mainline U-Boot for the original Zybo, SPL included, built from source.
#
# Unlike most Zynq boards this needs nothing out of Vivado: U-Boot carries the
# Zybo's ps7_init_gpl.c (DDR3 timings, MIO pinmux, PLLs) in-tree, and its Makefile
# selects it by CONFIG_DEFAULT_DEVICE_TREE. So the device tree name here is
# load-bearing twice: it picks the DDR init the SPL runs, not just the DT U-Boot
# reads. zynq-zybo-z7 would build fine and leave the original's RAM untrained.
{buildUBoot}:
buildUBoot {
  defconfig = "xilinx_zynq_virt_defconfig";
  extraConfig = ''
    CONFIG_DEFAULT_DEVICE_TREE="zynq-zybo"
  '';
  # boot.bin is the SPL wrapped in the BootROM's header, which is what BOOT.BIN
  # on the card has to be; the SPL then loads u-boot.img off the same partition.
  filesToInstall = ["spl/boot.bin" "u-boot.img"];
  extraMeta.platforms = ["armv7l-linux"];
}
