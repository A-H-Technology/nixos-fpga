# The DE25-Nano's U-Boot SPL, from Terasic's source: phase 1 of the board's
# HPS-first boot carries it (./README.md, "Phase 1"). Only the SPL is built:
# U-Boot proper stays the stock u-boot.itb (./uboot-stock.nix) it loads.
#
# The SPL must fit the HPS's 256 KiB of on-chip RAM (CONFIG_SPL_MAX_SIZE);
# with nixpkgs' GCC 15 it is 252 KiB.
{
  lib,
  buildUBoot,
  fetchFromGitHub,
}:
buildUBoot {
  version = "2025.01-terasic-de25-nano-revA-v1.0";
  src = fetchFromGitHub {
    owner = "terasic";
    repo = "u-boot-socfpga";
    rev = "d0f8813fd6bf8191d49c8b8d2035ffd2ae10c413"; # tag de25_nano_revA_v1.0
    hash = "sha256-0ke/T7DghftN84vUJ+uZoXe/JHLOsJ/xXnqCVi0+1oQ=";
  };
  defconfig = "socfpga_agilex5_de25_nano_defconfig";
  # Workaround: nixpkgs' cc-wrapper forces frame pointers on aarch64
  # (-fno-omit-frame-pointer -mno-omit-leaf-frame-pointer, even with all
  # hardening off; pkgs/build-support/cc-wrapper/default.nix, "enable_fp"; the
  # same default bites firmware in NixOS/nixpkgs#585479). Agilex 5's
  # save_boot_params is C (arch/arm/mach-socfpga/misc_soc64.c, unchanged in
  # mainline U-Boot as of 2026-02), and start.S branches to it at reset,
  # before any stack: with a frame record it stores through the reset SP and
  # the SPL dies before printing anything. Bisected on the board 2026-11-12,
  # GCC 15 objects into a booting GCC 11 SPL: misc_soc64.o alone hangs it.
  # Remove when save_boot_params is assembly (or naked) upstream, or when the
  # wrapper lets a build opt out of frame pointers.
  extraMakeFlags = ["KCFLAGS=-fomit-frame-pointer"];
  # U-Boot proper wants ATF's bl31.bin for its FIT; the SPL alone doesn't.
  buildFlags = ["spl/u-boot-spl.bin"];
  filesToInstall = ["spl/u-boot-spl-dtb.bin" "spl/u-boot-spl.map" ".config"];
  extraMeta.platforms = ["aarch64-linux"];
}
