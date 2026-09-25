# Firmware provenance

Everything in `firmware/` was copied off a Terasic DE25-Nano running Terasic's
stock SD card image, where the card's files are dated 2025-07-04. None of it is
modified. Nix applies the one config tweak (`LOCALVERSION_AUTO`) at build time,
so the file on disk stays byte-identical to the vendor original.

| File | Origin | sha256 |
|------|--------|--------|
| `u-boot.itb` | FAT partition of the stock card. U-Boot proper + ATF BL31 as a FIT image, loaded by the SPL in QSPI. | `bb6a48c77d2559a2f9710153cc616a242bfe701ff891cb5a14bddba33eaf2cf7` |
| `kernel.config` | `/proc/config.gz` on the running stock system, 2026-08-18. | `3ec2812cffb3c37bf677941283c9b65c3f5620b519cb58a4ded5f230cadbcdf7` |
| `de25-nano.dts.reference` | `dtc -I dtb -O dts` of the stock card's `socfpga_agilex5_de25_nano.dtb`. It's for reference only: the build uses the DTB from the kernel tree. | `c4f16d20e8d8c903d80216760dbebf6dbc2f7d3b96fffee6b69e9ee000b49239` |

`u-boot.itb` is a GPL-2.0+ binary. Its corresponding source is Terasic's
[u-boot-socfpga](https://github.com/terasic/u-boot-socfpga) and
[arm-trusted-firmware](https://github.com/ARM-software/arm-trusted-firmware).
Building it from source is on the roadmap. It isn't the default yet because a
U-Boot that doesn't match the SPL in QSPI leaves the board unbootable until you
reflash the card.

**Don't add files to `firmware/`.** Nix copies the directory as a unit, so any
change to its contents changes the kernel's store path and costs every user a
full kernel rebuild. Documentation belongs next to it, like this file.
