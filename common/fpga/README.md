# common/fpga (planned)

This is the planned home of a vendor-neutral `hardware.fpga` module. It will
declare bitstreams (`.rbf`/`.bit.bin`) and their device-tree overlays, and load
them at boot through the kernel's fpga-manager. Board modules will provide the
vendor-specific parts: the manager driver and the bridges.

Nothing here yet. See the roadmap in the top-level README.
