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

  # What linuxManualConfig would otherwise learn by reading `configfile` back
  # through import-from-derivation (which needs an aarch64 builder just to
  # *evaluate*, breaking `nix flake check` on x86). The source file is right
  # here, so parse it purely instead; same regex as nixpkgs' readConfig, and the
  # one sed below only touches LOCALVERSION_AUTO, which no eval decision reads.
  config = lib.listToAttrs (lib.concatMap (line: let
    m = lib.match "(CONFIG_[^=]+)=([ym])" line;
  in
    lib.optional (m != null) {
      name = lib.elemAt m 0;
      value = lib.elemAt m 1;
    }) (lib.splitString "\n" (builtins.readFile ../firmware/kernel.config)));

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
      inherit config configfile;
    })).overrideAttrs (old: {
    passthru =
      old.passthru
      // {
        # Repo-relative, run from the repo root by `nix run .#update`.
        updateScript = ["terasic/de25-nano/kernel/update.sh" "terasic/de25-nano/kernel/source.json"];
      };
  })
