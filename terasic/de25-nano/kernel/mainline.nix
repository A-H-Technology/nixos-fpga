# Mainline Linux for the DE25-Nano: nixpkgs' kernel plus the patches in
# ./mainline, which add the board's device tree and what it needs below it.
#
# Mainline 7.4 has the SD6HC driver Agilex 5's SD controller needs, but not
# yet its node in socfpga_agilex5.dtsi (0001, Altera's own, v7 of
# https://lore.kernel.org/r/20260901184828.15653-1-tanmay.kathpalia@altera.com).
# 0002-0005 are ours and are going upstream once this boots: the FPGA
# manager node (no driver change, since the service layer already maps its
# buffers through the SMMU) and the board itself. Drop each patch as the
# kernel it applies to gains it; when all five are gone, so is this file.
#
# linux_testing because 7.4 is still an rc; switch to linux_latest once it
# ships.
{
  lib,
  linux_testing,
  # linuxPackagesFor re-calls the kernel via `.override { kernelPatches features
  # randstructSeed }`, which lands here since this file is callPackage'd; pass
  # them on, with its patches after ours. Not a named argument: callPackage
  # would fill that from pkgs.kernelPatches.
  ...
} @ args:
linux_testing.override (removeAttrs args ["lib" "linux_testing"]
  // {
    # Overriding replaces nixpkgs' own patches (bridge_stp_helper and co), so
    # carry them along.
    kernelPatches =
      linux_testing.kernelPatches
      ++ map (file: {
        name = lib.removeSuffix ".patch" (baseNameOf file);
        patch = file;
      }) (lib.filesystem.listFilesRecursive ./mainline)
      ++ args.kernelPatches or [];

    # The module empties the initrd (default.nix explains why), so the whole
    # root path has to be built in, and nixpkgs builds the SD host as a module.
    structuredExtraConfig = with lib.kernel; {
      ARCH_INTEL_SOCFPGA = yes;
      MMC_SDHCI_PLTFM = yes;
      MMC_SDHCI_CADENCE = yes;
      INTEL_STRATIX10_SERVICE = yes;
      FPGA_MGR_STRATIX10_SOC = module;
      FPGA_REGION = module;
      OF_FPGA_REGION = module;
      UIO_PDRV_GENIRQ = module;
    };
  })
