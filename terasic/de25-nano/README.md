# Terasic DE25-Nano

An Agilex 5 SoC FPGA dev board. This module covers the HPS (ARM) side:

- 2x Cortex-A76 + 2x Cortex-A55
- ~957 MB LPDDR4
- gigabit ethernet
- microSD

The fabric loads from Linux through [common/fpga](../../common/fpga), once the
board has booted an HPS-first image. See [Fabric](#fabric).

## Use it

```nix
{
  inputs.nixos-fpga.url = "github:A-H-Technology/nixos-fpga";

  outputs = { nixpkgs, nixos-fpga, ... }: {
    nixosConfigurations.my-board = nixpkgs.lib.nixosSystem {
      modules = [
        nixos-fpga.nixosModules.terasic-de25-nano
        nixos-fpga.nixosModules.terasic-de25-nano-sd-image # omit if you lay out the card yourself
        {
          nixpkgs.hostPlatform = "aarch64-linux";
          # ...your config
        }
      ];
    };
  };
}
```

Build the image with `nix build .#nixosConfigurations.my-board.config.system.build.sdImage`.
Or grab the example image, which autologins `nixos` on serial:

```sh
nix build github:A-H-Technology/nixos-fpga#sd-image-terasic-de25-nano
sudo dd if=result of=/dev/sdX bs=4M conv=fsync status=progress
```

Build on an aarch64 machine or on x86 with
`boot.binfmt.emulatedSystems = ["aarch64-linux"]`, and add the
[binary cache](../../README.md#binary-cache) so the kernel isn't compiled
locally. The board has 957 MB of RAM, so don't build on it. Deploy closures to
it from elsewhere, and set `nix.settings.max-jobs = 1` in its config.

## Console

Serial only, `ttyS0` at 115200 8N1. HDMI is driven from the fabric, so there's
no display unless your FPGA design provides one.

A good boot shows this line on serial, then extlinux's menu:

```
de25-nano: handing off to extlinux on mmc 0:2
```

## Boot chain

```
QSPI (read by the SDM at power-on: HPS-first phase 1, U-Boot SPL)          <- phase1.nix
  -> SPL loads u-boot.itb from the card's FAT partition                     <- stock blob (BL31 rebuilt on mainline)
    -> boot.scr.uimg: sets ramdisk_addr_r, sysboot                         <- generated
      -> /boot/extlinux/extlinux.conf on the ext4 root                       <- NixOS generations
```

Every generation is bootable from the extlinux menu, so rollback works as on
any NixOS machine. The comments in `boot-script.nix` and `sd-image.nix` explain
each workaround.

## Fabric

Linux loads the fabric through the SDM (driver `stratix10-soc`, manager
`intel,agilex5-soc-fpga-mgr`), with `/dev/fpga-load` or
`hardware.fpga.bitstream` from [common/fpga](../../common/fpga). Two
conditions apply, both from the Agilex 5 boot model:

- **The board must boot HPS-first.** In that mode the SDM configures only the
  HPS I/O and the HPS EMIF, starts the HPS, and leaves the fabric for later.
  Agilex 5 lets the HPS configure the fabric only in this mode. Terasic's
  factory QSPI image is FPGA-first (its GHRD scripts run `quartus_pfg` without
  `-o hps=on`). Writing a full FPGA-first `.rbf` to the manager from a booted
  HPS wedges the SDM ("timeout waiting for svc layer buffers") until the HPS
  reboots.
- **The bitstream is the `.core.rbf`** that `quartus_pfg -c design.sof
  design.rbf -o hps_path=u-boot-spl-dtb.hex -o hps=on` splits off. Its design
  sets `HPS_INITIALIZATION "HPS FIRST"`. The SDM takes it only if its HPS I/O
  hash (`quartus_pfg -i design.core.rbf`) matches the phase-1 image the board
  booted. In practice, every design must instantiate the same HPS IP.

The phase-1 image (HPS I/O, HPS EMIF, U-Boot SPL) comes from QSPI as a `.jic`,
or over JTAG for testing. See [Phase 1](#phase-1).

## Phase 1

`phase1-terasic-de25-nano` builds it with no Quartus:

```sh
nix build github:A-H-Technology/nixos-fpga#phase1-terasic-de25-nano
quartus_pgm -c "DE25-Nano [3-10-iface0]" -m jtag -o "p;result/qspi.jic@1"   # into QSPI
quartus_pgm -c "DE25-Nano [3-10-iface0]" -m jtag -o "p;result/hps.rbf"      # or for one boot
```

"One boot" means it: after a JTAG load, a Linux reboot never reaches the SPL
(2026-11-18: nothing on the console after `reboot: Restarting system`), so
load it again or power-cycle. Booted from QSPI, a reboot comes back.

The SPL is `uboot-spl-terasic-de25-nano`, Terasic's `de25_nano_revA_v1.0`
source built by nixpkgs' compiler. The rest comes from
[agilex5-re](https://github.com/cramt/agilex5-re)'s `phase1/de25-nano`:
Quartus' build of the board's HPS I/O and EMIF settings, with Altera's SDM
firmware. [chipsmith](https://github.com/A-H-Technology/chipsmith) puts the
SPL into it and packs the `.jic`, so the result keeps that build's HPS IO hash
(`result/hps_io_hash`). Every `.core.rbf` built against `result/shell.txt`
loads after it.

The SPL has to be built without frame pointers, which nixpkgs' compiler wrapper
otherwise forces on aarch64. Terasic's `save_boot_params` is C, and `start.S`
calls it before there is a stack. With a frame record it writes through the
reset SP and the SPL hangs before printing anything (bisected on the board,
2026-11-12; `uboot-spl.nix` has the details). An earlier GCC 16 build failed
the same way, not because of the compiler's age.

Booted on hardware 2026-11-12: over JTAG (SPL, DDR calibration, ATF, the
stock `u-boot.itb`, NixOS up to the login prompt), then written to QSPI and
booted from it after a power cycle with no JTAG. A chipsmith-built
`.core.rbf` then loaded from Linux (examples/de25-irq: GIC bit 17 at 3.0 Hz,
bit 20 25 % high).

The HPS-to-FPGA bridges come up with the core. Before a load the reset
manager holds all four in reset (`BRGMODRST`, 0x10d1102c, reads `0xF`); after
a `.core.rbf` loads through `/dev/fpga-load` it reads `0x0`, and the
lightweight bridge carries traffic with no driver and no ATF call. Tested
2026-11-12 with designs/hpsf's core from agilex5-re, which answers on it:
`devmem 0x20000000` reads `0x48505346` ("HPSF") and `0x20000004` the design's
50 MHz counter. The lightweight bridge is the first 512 MiB of the fabric
window at 0x20000000. A read there with no core answering (or none loaded)
hangs the bus until the HPS is reset.

`/dev/uio*` named `lwhps2fpga` (`lwBridgeUio`, on by default) maps the bottom
64 KiB of the lightweight bridge window and takes `f2h_irq0[0]` as its
interrupt, so a userspace driver for a register block in the fabric can sleep
in `read()` instead of polling. `f2h_irq0[n]` is GIC SPI 17 + n. The node is
a device-tree overlay and `uio_pdrv_genirq` is told its compatible
(`of_id=generic-uio`).

The FPGA-to-HPS bridge (in phase 1 since 2026-11-18) also needs no enable,
but every access goes through the SMMU under the stream ID the master puts on
AxMMUSID. A stream Linux gave a device (1-10) faults, one nobody has is
aborted; both answer SLVERR. `fpga2hpsStream` (on by default, stream 11)
holds a stream with a generic-uio node (`/dev/uio*` "fpga2hps", no registers)
and `fpga2hps-stream.service` switches its IOMMU group to `identity`, so a
master using stream 11 reaches physical memory, coherent with the CPUs'
caches if its accesses are shareable and write-back. Tested 2026-11-18 with
chipsmith's examples/de25-f2h: the fabric writes and reads 16 pages of a
process's buffer, every word right both ways with no cache maintenance.

U-Boot's `bridge enable` (`fpgaBridges.enable`) is off by default: in an
HPS-first boot it runs before the fabric exists, and U-Boot prints `FPGA not
ready. Bridge reset aborted!`.

Loaded on hardware 2026-11-09: a GHRD-HPS design's `.core.rbf` (1015808 bytes)
loaded in 2.1 s and reloaded. The manager reported `operating` with a clean
dmesg, and the design's FPGA-to-HPS interrupt lines read back from the GIC.

## Options

All options live under `hardware.terasic.de25-nano`:

| Option | Default | What it's for |
|--------|---------|---------------|
| `kernelSource` | `"terasic"` | `"mainline"` boots nixpkgs' kernel (7.4-rc) with the board's device tree patched in ([kernel/mainline.nix](kernel/mainline.nix)). Not hardware-tested yet. |
| `kernel` | the one `kernelSource` names | Use `.override`/`.overrideAttrs` to change it. A different kernel means building it yourself. |
| `uboot` | stock `u-boot.itb` ([provenance](PROVENANCE.md)); on mainline, with BL31 from Altera's TF-A ([below](#bl31)) | Any package with a `u-boot.itb` at its root. Installed on the FAT partition at boot and on every switch; the replaced one is kept as `u-boot.itb.prev`. |
| `phase1HpsIoHash` | the flake's phase 1's (agilex5-re `phase1/de25-nano`) | Installed as `/etc/fpga/phase1/hps_io_hash`: `chipsmith flash --ssh` refuses a core for another phase 1, which would wedge the SDM. It says what the system was built for; the QSPI is written by hand and Linux can't read it back. |
| `fpgaBridges.enable` | `false` | Runs `bridge enable` in U-Boot, for an FPGA-first QSPI image. HPS-first, the core's load raises the bridges. |
| `lwBridgeUio.enable` | `true` | `/dev/uio*` "lwhps2fpga" over the lightweight bridge, with an f2h_irq0 interrupt. |
| `lwBridgeUio.size` / `.irq` | `65536` / `0` | Bytes mapped from 0x20000000; which f2h_irq0 bit. |
| `fpga2hpsStream.enable` / `.sid` | `true` / `11` | An identity SMMU stream for FPGA-to-HPS masters. |
| `bootScript.extraCommands` | `""` | U-Boot commands run just before extlinux. |

The fabric's options are `hardware.fpga.*` ([common/fpga](../../common/fpga)).
This module sets the manager and driver. `hardware.fpga.bitstream` takes a
`.core.rbf` that matches the HPS-first image the board boots.

## Known limits

- **No nftables on Terasic's kernel.** Their config doesn't build it, so with
  `kernelSource = "terasic"` the module switches the NixOS firewall to the
  iptables-legacy backend. The mainline kernel has nftables.
- **Mainline needs patches.** The board's DTB exists only in Terasic's fork.
  Terasic's kernel tracks their `de25-nano-6.12.11-lts` branch, and new
  kernel base branches are adopted by hand after a hardware test. The
  mainline kernel carries Altera's SD controller node and our board DT
  ([kernel/mainline](kernel/mainline)) until they land upstream. The SDM's
  temperature and voltage sensors need no DT node there: the service layer
  creates `socfpga-hwmon` itself.
- **Stock U-Boot proper.** The SPL builds from source, U-Boot proper is still
  the stock `u-boot.itb`, and so is BL31 on Terasic's kernel. See
  [PROVENANCE.md](PROVENANCE.md).
- **A bad `u-boot.itb` needs the card in another machine.** The SPL loads
  exactly one file and has no fallback, so the board stays silent after
  `## Checking hash(es) for Image fdt-0 ... OK`. Copy `u-boot.itb.prev` (or
  `.stock`) back over `u-boot.itb` on the FAT partition.

## BL31

On `kernelSource = "mainline"` the stock `u-boot.itb` carries BL31 from
Altera's TF-A (`socfpga_v2.15.0`, [bl31.nix](bl31.nix)) in place of Terasic's
v2.12 build ([uboot-bl31.nix](uboot-bl31.nix) repacks it; U-Boot proper and
its DTB are the stock bytes). Mainline's service layer breaks on the stock
BL31 in two ways, both found on the board 2026-11-19:

- An SiP async poll on a request the SDM hasn't finished returns
  `STATUS_ERROR` (or a raw -2) instead of `NO_RESPONSE`, so the kernel reuses
  a job ID that's still in flight and every hwmon read returns the previous
  channel's value (the 1.8 V rail reads 0.83 V).
- Synchronous calls (FPGA configuration) and async ones (hwmon) both read the
  SDM's response FIFO and steal each other's responses: a load next to a
  hwmon read fails, then fpga-mgr hangs waiting for buffers and the board
  needs a power cycle (a soft reboot hangs too).

Altera's tree defaults BL31's console to UART0, which hangs the DE25 silently
right after the SPL; `SOCFPGA_UART_CONFIG=1` moves it to UART1, as Terasic's
tree hardcodes. Two more fixes ride on top:

- [bl31-cmd-desc-wrap.patch](bl31-cmd-desc-wrap.patch): BL31's command
  descriptor search never wraps around, so once a scan finds the last two
  slots busy (an FPGA load next to hwmon reads does it in minutes), every
  async send fails with `MBOX_BUFFER_FULL` until a reboot. Still in Altera's
  and upstream TF-A.
- Kernel patch 0006, in socfpga-hwmon: a read that times out while the SDM is
  busy (during a load) no longer frees a job ID the SDM still owes a response
  to, which shifted every later reading by one channel.

A soft reboot works on this BL31 even after the bugs above have struck; on the
stock one it hung at `reboot: Restarting system` until a power cycle.

Tested 2026-11-19 on a mainline 7.4-rc2 kernel: every sensor read in a loop
for 10 minutes (17,115 reads) with a `.core.rbf` loaded every 15 s alongside
(35 loads). Every load ended `operating`, every reading was in range, and the
only misses were 144 `EAGAIN`s from the temperature sensor while the SDM was
configuring. The same loop without loads: 17,003 reads, none bad.
