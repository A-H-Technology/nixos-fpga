# TF-A's BL31 for the DE25-Nano, from Altera's fork, which ./uboot-bl31.nix
# puts in place of the one in Terasic's stock u-boot.itb.
#
# The stock BL31 (Terasic's de25-nano-v2.12.0) breaks mainline's stratix10-svc
# in two ways:
# - It answers an SiP V3 async poll on a request the SDM hasn't finished with
#   STATUS_ERROR or a raw -2 instead of NO_RESPONSE, so the kernel frees the job
#   ID and reuses it, and every later poll gets the previous request's response
#   (socfpga_hwmon reads each sensor's value on the next one). Fixed in Altera's
#   6152b407e4.
# - V1 sync calls (FPGA configuration) read the SDM response FIFO directly while
#   the V3 async state machine (hwmon) reads the same FIFO, so each steals the
#   other's responses: an FPGA load next to a hwmon read fails, and fpga-mgr
#   hangs waiting for buffers the SDM never returns. Altera's tree routes V1
#   through the V3 response queue (mailbox_queue_consume).
#
# ./bl31-cmd-desc-wrap.patch fixes a third, still in Altera's and upstream
# TF-A as of 2026-11-19: the command descriptor search never wraps, so one
# unlucky scan makes every later async send fail with MBOX_BUFFER_FULL. Drop
# it once the pinned tree's mailbox_get_free_cmd_desc() wraps.
{
  buildArmTrustedFirmware,
  fetchFromGitHub,
}:
buildArmTrustedFirmware {
  version = "2.15.0-altera-09c4dc6";
  src = fetchFromGitHub {
    owner = "altera-fpga";
    repo = "arm-trusted-firmware";
    rev = "09c4dc6628810d8570af69db43918d344f9e80e9"; # socfpga_v2.15.0
    hash = "sha256-hQMbgSKHvLQiMcAjBsktEiY/DhNLrBUmbZ/c95HkE9c=";
  };
  # Replaces nixpkgs' remove-hdcp-blob.patch, which is for the RK3399 only.
  patches = [./bl31-cmd-desc-wrap.patch];
  platform = "agilex5";
  extraMakeFlags = [
    # The board's console is UART1. Terasic's tree hardcodes it; Altera's
    # defaults to UART0, which is held in reset here, so BL31's first putc
    # spins forever and the board hangs silently after the SPL.
    "SOCFPGA_UART_CONFIG=1"
    "bl31"
  ];
  filesToInstall = ["build/agilex5/release/bl31.bin"];
  extraMeta.platforms = ["aarch64-linux"];
}
