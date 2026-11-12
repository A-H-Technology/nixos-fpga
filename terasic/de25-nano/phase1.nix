# Phase 1 of the DE25-Nano's HPS-first boot with this repo's SPL
# (./uboot-spl.nix): what the SDM loads from QSPI at power-on (README.md,
# "Phase 1"). Outputs:
#
#   hps.rbf       phase 1, for a JTAG load (quartus_pgm -m jtag -o "p;hps.rbf")
#   qspi.jic      the QSPI image (quartus_pgm -m jtag -o "p;qspi.jic@1")
#   shell.txt     the HPS shell lines a core is built on
#   hps_io_hash   the HPS IO hash a core must carry to load after it
#
# Everything but the SPL is agilex5-re's phase1/de25-nano (Quartus' build of
# the board's HPS I/O and EMIF, with Altera's SDM firmware): chipsmith rebuilds
# its HPS section around the SPL and packs the .jic, so no Quartus runs here.
{
  runCommand,
  # chipsmith (unwrapped) for the build platform: `agilex5-phase1`.
  chipsmith,
  # agilex5-re's packages: `db` (the keyed-hash key) and `phase1`.
  agilex5-db,
  agilex5-phase1,
  uboot-spl,
}:
runCommand "phase1-terasic-de25-nano" {
  CHIPSMITH_AGILEX5_DB = agilex5-db;
} ''
  mkdir -p $out
  ${chipsmith}/bin/chipsmith agilex5-phase1 \
    ${agilex5-phase1}/de25-nano/hps.rbf ${uboot-spl}/u-boot-spl-dtb.bin \
    --rbf $out/hps.rbf --jic $out/qspi.jic
  cp ${agilex5-phase1}/de25-nano/{shell.txt,hps_io_hash} $out/
''
