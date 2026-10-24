# Vendor-neutral FPGA loading: /dev/fpga-load (see ./fpga-load/fpga-load.c)
# on top of the kernel's fpga-manager, and optionally a bitstream loaded at
# every boot. Board modules import this and set `manager` and `driver`.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.hardware.fpga;
in {
  options.hardware.fpga = {
    manager = lib.mkOption {
      type = lib.types.str;
      example = "xlnx,zynq-devcfg-1.0";
      description = "DT compatible of the node the board's fpga-manager driver binds to.";
    };

    driver = lib.mkOption {
      type = lib.types.str;
      example = "zynq-fpga";
      description = ''
        Kernel module of the board's fpga-manager driver. Loaded before
        fpga-load, so the manager is there by the time anything writes to
        /dev/fpga-load.
      '';
    };

    bitstream = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Bitstream to load at boot, in the format the board's manager takes (see
        the board's README). Without one the fabric stays as the boot chain
        left it, and `/dev/fpga-load` is still there for loading by hand.
      '';
    };
  };

  config = {
    boot.extraModulePackages = [(config.boot.kernelPackages.callPackage ./fpga-load {})];
    boot.kernelModules = ["fpga-load"];
    boot.extraModprobeConfig = ''
      options fpga-load manager=${cfg.manager}
      softdep fpga-load pre: ${cfg.driver}
    '';

    # Group access so deploy tooling can load over ssh without root.
    users.groups.fpga = {};
    services.udev.extraRules = ''
      KERNEL=="fpga-load", GROUP="fpga", MODE="0660", TAG+="systemd"
    '';

    systemd.services.fpga-load = lib.mkIf (cfg.bitstream != null) {
      description = "Load the FPGA bitstream";
      wantedBy = ["multi-user.target"];
      requires = ["dev-fpga\\x2dload.device"];
      after = ["dev-fpga\\x2dload.device"];
      # The softdep loads the manager's driver first, but a driver that binds
      # asynchronously can still be late; the load then fails with ENODEV and
      # a retry covers it.
      startLimitIntervalSec = 60;
      startLimitBurst = 10;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = 2;
        ExecStart = "${pkgs.coreutils}/bin/dd if=${cfg.bitstream} of=/dev/fpga-load bs=1M";
      };
    };
  };
}
