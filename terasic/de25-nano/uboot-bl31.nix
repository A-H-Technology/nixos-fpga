# Terasic's stock u-boot.itb (./uboot-stock.nix) with only its BL31 replaced by
# ./bl31.nix, which fixes the SiP async poll the mainline kernel's service
# layer relies on. U-Boot proper and its DTB are the stock bytes, unpacked and
# packed again into the same FIT layout the SPL in QSPI already loads.
#
# The signature node is the stock one, unsigned like the original (the SPL's
# DTB has no required key, so it checks only the crc32 hashes).
{
  lib,
  runCommand,
  buildPackages,
  callPackage,
  uboot-stock ? callPackage ./uboot-stock.nix {},
  bl31 ? callPackage ./bl31.nix {},
}:
runCommand "u-boot-de25-nano-bl31-${bl31.version}" {
  nativeBuildInputs = [buildPackages.ubootTools buildPackages.dtc];
  meta = {
    description = "Stock U-Boot FIT image for the Terasic DE25-Nano with BL31 from Altera's TF-A";
    license = lib.licenses.gpl2Plus;
    platforms = ["aarch64-linux"];
  };
} ''
  stock=${uboot-stock}/u-boot.itb
  # Image 0 is U-Boot proper, 2 its DTB (dumpimage -l lists them).
  dumpimage -T flat_dt -p 0 -o u-boot-nodtb.bin $stock
  dumpimage -T flat_dt -p 2 -o u-boot.dtb $stock
  cp ${bl31}/bl31.bin .

  cat > u-boot.its <<'EOF'
  /dts-v1/;
  / {
    description = "FIT with firmware and bootloader";
    #address-cells = <1>;
    images {
      uboot {
        description = "U-Boot SoC64";
        data = /incbin/("u-boot-nodtb.bin");
        type = "standalone";
        os = "U-Boot";
        arch = "arm64";
        compression = "none";
        load = <0x80200000>;
        hash { algo = "crc32"; };
      };
      atf {
        description = "ARM Trusted Firmware";
        data = /incbin/("bl31.bin");
        type = "firmware";
        os = "arm-trusted-firmware";
        arch = "arm64";
        compression = "none";
        load = <0x80000000>;
        entry = <0x80000000>;
        hash { algo = "crc32"; };
      };
      fdt-0 {
        description = "socfpga_socdk";
        data = /incbin/("u-boot.dtb");
        type = "flat_dt";
        compression = "none";
        hash { algo = "crc32"; };
      };
    };
    configurations {
      default = "board-0";
      board-0 {
        description = "board_0";
        firmware = "atf";
        loadables = "uboot";
        fdt = "fdt-0";
        signature {
          algo = "crc32";
          key-name-hint = "dev";
          sign-images = "atf", "uboot", "fdt-0";
        };
      };
    };
  };
  EOF

  # External data, as in the stock image.
  mkimage -E -f u-boot.its u-boot.itb
  dumpimage -l u-boot.itb
  install -Dm644 u-boot.itb $out/u-boot.itb
''
