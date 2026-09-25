# Adding a board

Boards live at `<vendor>/<board>/`, using nixos-hardware's layout.

1. **`<vendor>/<board>/default.nix`** is the board module. Importing it enables
   it, so there's no `enable` flag. Board options go under
   `hardware.<vendor>.<board>`. Keep them to real choices. Constants like load
   addresses stay internal, with a comment saying why they have those values.
2. **Kernel.** If the board needs a vendor fork, put it in `kernel/` with a
   `source.json` and an `update.sh` exposed as `passthru.updateScript`. See
   `terasic/de25-nano/kernel/` for the pattern: `version` is parsed from the
   tree's own Makefile, so `modDirVersion` can't drift.
3. **Blobs.** Put any binary the build ships in `firmware/`, next to a
   `PROVENANCE.md` that records where it came from, when, its sha256, and where
   its source is.
4. **Example.** Add `examples/<vendor>-<board>.nix`: the smallest config that
   boots to a shell.
5. **Flake.** Add the module to `nixosModules`, the packages to `overlays.default`
   and `packages`, and one entry to `checks.aarch64-linux`. CI and the updater
   pick the board up from those.
6. **Proof.** The PR needs a serial log of the example image booting on real
   hardware.

## Where shared code goes

Nothing goes in `common/` until a second board needs it. Code shared from a
single board is only a guess at what the second one will need.
