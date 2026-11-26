# sd-image.nix's first-boot expand-root-partition reads the root partition's
# number from `lsblk -npo MAJ:MIN`, which util-linux 2.42 pads ("179:2  "), so
# sfdisk gets -N"2  ", refuses it, and the root stays at the image's size (a
# DE25-Nano reflashed 2026-11-26 came up with 7 GB of a 30 GB card, 96% full).
# The unit only runs while /nix-path-registration exists, so a failed first
# boot never retries.
#
# This is nixpkgs PR #590509's script, which asks the kernel instead:
# https://github.com/NixOS/nixpkgs/pull/590509 (issue #554294). Drop this
# file once that PR is in the pinned nixpkgs.
{
  lib,
  pkgs,
  ...
}: {
  systemd.services.expand-root-partition.script = lib.mkForce ''
    rootPart=$(${lib.getExe' pkgs.util-linux "findmnt"} -n -o SOURCE /)
    bootDevice=$(${lib.getExe' pkgs.util-linux "lsblk"} -npo PKNAME "$rootPart")
    partNum=$(< "/sys/class/block/''${rootPart##*/}/partition")

    echo ",+," | ${lib.getExe' pkgs.util-linux "sfdisk"} -N"$partNum" --no-reread "$bootDevice"
    ${lib.getExe' pkgs.parted "partprobe"}
    ${lib.getExe' pkgs.e2fsprogs "resize2fs"} "$rootPart"
  '';
}
