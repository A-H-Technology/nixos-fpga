# common/fpga

Vendor-neutral FPGA loading on top of the kernel's fpga-manager. Board modules
import it and set the two board-specific options; users set at most one.

| Option | Set by | What it's for |
|--------|--------|---------------|
| `hardware.fpga.manager` | the board module | DT compatible of the node the board's fpga-manager driver binds to (`xlnx,zynq-devcfg-1.0` on a Zynq). |
| `hardware.fpga.driver` | the board module | Kernel module of that driver (`zynq-fpga`), loaded before `fpga-load` so the manager is there first. |
| `hardware.fpga.bitstream` | you | A bitstream to load at every boot, in the format the board's manager takes. `null` (the default) leaves the fabric as the boot chain left it. |

## /dev/fpga-load

Mainline Linux has no way for userspace to start a load. fpga-manager's sysfs
is read-only (the Xilinx fork's `firmware` attribute never went upstream), and
the in-kernel route, a device-tree overlay on an fpga-region, needs an overlay
interface mainline doesn't have either. So this module ships a small
out-of-tree kernel module, `fpga-load` (`./fpga-load`), built against
`boot.kernelPackages`:

```sh
cat design.bin > /dev/fpga-load    # loads on close; close() returns the result
cat /sys/class/fpga_manager/fpga0/state    # operating
```

The device belongs to the `fpga` group (mode 0660), so deploy tooling can load
over ssh without root. One writer at a time.

The bitstream format is whatever the board's manager driver takes. For a Zynq
that's the `.bit` payload with every 32-bit word byte-swapped (Xilinx's
"byte-swapped `.bin`"); chipsmith writes it next to the `.bit` and loads it
with `chipsmith flash --ssh HOST`.

## Boards

- [Digilent Zybo](../../digilent/zybo): Zynq devcfg (PCAP). Loaded on hardware
  2026-10-24.
- Terasic DE25-Nano: not wired up yet. Its kernel has the Stratix 10 SoC
  manager (`FPGA_MGR_STRATIX10_SOC`), which goes through the SDM.
