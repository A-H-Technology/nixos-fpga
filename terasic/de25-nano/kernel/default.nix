# Terasic's linux-socfpga fork, built with the exact config Terasic ships.
#
# Mainline has had Agilex 5 SoC support since 6.6, but socfpga_agilex5_de25_nano.dtb
# exists only in this fork, so nixpkgs' kernels can't boot the board. Revisit
# once the board DT lands upstream.
{
  lib,
  fetchFromGitHub,
  linuxManualConfig,
  runCommand,
  # linuxPackagesFor re-calls the kernel via `.override { kernelPatches features
  # randstructSeed }`, which lands here since this file is callPackage'd; pass
  # those through to linuxManualConfig untouched.
  ...
} @ args: let
  passthroughArgs = removeAttrs args ["lib" "fetchFromGitHub" "linuxManualConfig" "runCommand"];

  # Written by ./update.sh, never by hand: `version` is parsed out of the tree's
  # own Makefile at `rev`, so modDirVersion can't drift from the source and
  # silently break module loading.
  source = lib.importJSON ./source.json;

  # Extracted verbatim from the running stock board via /proc/config.gz, so this
  # is the config Terasic actually validated rather than a reconstruction. Every
  # option NixOS requires (systemd's namespaces/seccomp/cgroups/tmpfs-ACL set) is
  # already present, and all MMC drivers are =y so the initrd finds root without
  # any modules.
  #
  # CONFIG_LOCALVERSION_AUTO appends "-g<sha>" from git describe. fetchFromGitHub
  # gives a tarball with no .git, so that suffix silently vanishes and stops
  # matching modDirVersion. Pin it off rather than encode a hash we can't
  # reproduce.
  #
  # Reads from the whole ../firmware directory rather than just the one file on
  # purpose: that keeps this derivation byte-identical to the one the board was
  # first brought up with, so moving it here cost no ~26 min ARM rebuild.
  configfile = runCommand "de25-nano-kernel.config" {} ''
    sed 's/^CONFIG_LOCALVERSION_AUTO=y$/# CONFIG_LOCALVERSION_AUTO is not set/' \
      ${../firmware}/kernel.config > "$out"
  '';
in
  (linuxManualConfig (passthroughArgs
    // {
      inherit (source) version;
      modDirVersion = source.version;
      src = fetchFromGitHub {
        inherit (source) owner repo rev hash;
      };
      inherit configfile;
      allowImportFromDerivation = true;
    })).overrideAttrs (old: {
    passthru =
      old.passthru
      // {
        # Repo-relative, run from the repo root by `nix run .#update`.
        updateScript = ["terasic/de25-nano/kernel/update.sh" "terasic/de25-nano/kernel/source.json"];
      };
  })
