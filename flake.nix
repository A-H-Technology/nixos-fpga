{
  description = "NixOS hardware support for FPGA and SoC-FPGA boards";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # The DE25-Nano's phase 1: agilex5-re ships the board's HPS I/O and EMIF
    # build, chipsmith puts our SPL into it (terasic/de25-nano/phase1.nix).
    agilex5-re.url = "github:cramt/agilex5-re";
    chipsmith = {
      url = "github:A-H-Technology/chipsmith";
      inputs.agilex5-re.follows = "agilex5-re";
    };
  };

  outputs = {
    self,
    nixpkgs,
    agilex5-re,
    chipsmith,
  }: let
    inherit (nixpkgs) lib;

    # aarch64 boards build natively (CI uses GitHub's ARM runners). 32-bit ARM
    # boards are cross-built from x86_64 instead: Hydra caches nothing for
    # armv7l, so a native build compiles everything anyway, and cross keeps it
    # on whatever x86 machine is at hand. Tooling runs anywhere.
    toolSystems = ["x86_64-linux" "aarch64-linux"];
    forToolSystems = f: lib.genAttrs toolSystems (s: f nixpkgs.legacyPackages.${s});

    aarch64Pkgs = nixpkgs.legacyPackages.aarch64-linux;
    x86Pkgs = nixpkgs.legacyPackages.x86_64-linux;

    example = name: platform: modules:
      lib.nixosSystem {
        modules = modules ++ [./examples/${name}.nix {nixpkgs = platform;}];
      };

    # Phase 1 for the DE25-Nano with SPL from `pkgs` (native or cross), packed
    # by chipsmith on the machine doing the build.
    de25Phase1 = pkgs: let
      build = pkgs.stdenv.buildPlatform.system;
    in
      pkgs.callPackage ./terasic/de25-nano/phase1.nix {
        chipsmith = chipsmith.packages.${build}.chipsmith.unwrapped;
        agilex5-db = agilex5-re.packages.${build}.db;
        agilex5-phase1 = agilex5-re.packages.${build}.phase1;
        uboot-spl = pkgs.callPackage ./terasic/de25-nano/uboot-spl.nix {};
      };

    sdImageOf = pkgs: name: config:
      pkgs.runCommand "sd-image-${name}" {} ''
        cp ${config.system.build.sdImage}/sd-image/*.img $out
      '';
  in {
    nixosModules = {
      terasic-de25-nano = ./terasic/de25-nano;
      terasic-de25-nano-sd-image = ./terasic/de25-nano/sd-image.nix;
      digilent-zybo = ./digilent/zybo;
      digilent-zybo-sd-image = ./digilent/zybo/sd-image.nix;
    };

    overlays.default = final: _prev: {
      linux-terasic-de25-nano = final.callPackage ./terasic/de25-nano/kernel {};
      linuxPackages-terasic-de25-nano = final.linuxPackagesFor final.linux-terasic-de25-nano;
      uboot-terasic-de25-nano-stock = final.callPackage ./terasic/de25-nano/uboot-stock.nix {};
      uboot-spl-terasic-de25-nano = final.callPackage ./terasic/de25-nano/uboot-spl.nix {};
      phase1-terasic-de25-nano = de25Phase1 final;
      uboot-digilent-zybo = final.callPackage ./digilent/zybo/uboot.nix {};
    };

    nixosConfigurations = {
      terasic-de25-nano-example = example "terasic-de25-nano" {hostPlatform = "aarch64-linux";} [
        self.nixosModules.terasic-de25-nano
        self.nixosModules.terasic-de25-nano-sd-image
      ];

      digilent-zybo-example =
        example "digilent-zybo" {
          hostPlatform = "armv7l-linux";
          buildPlatform = "x86_64-linux";
        } [
          self.nixosModules.digilent-zybo
          self.nixosModules.digilent-zybo-sd-image
        ];
    };

    packages = {
      aarch64-linux = let
        overlaid = self.overlays.default aarch64Pkgs aarch64Pkgs;
      in {
        inherit (overlaid) linux-terasic-de25-nano uboot-terasic-de25-nano-stock uboot-spl-terasic-de25-nano phase1-terasic-de25-nano;
        sd-image-terasic-de25-nano =
          sdImageOf aarch64Pkgs "terasic-de25-nano"
          self.nixosConfigurations.terasic-de25-nano-example.config;
      };

      # Cross-built, so these store paths only match a user's own build if they
      # also cross from x86_64. A native armv7l builder gets cache misses.
      x86_64-linux = {
        uboot-spl-terasic-de25-nano = x86Pkgs.pkgsCross.aarch64-multiplatform.callPackage ./terasic/de25-nano/uboot-spl.nix {};
        phase1-terasic-de25-nano = de25Phase1 x86Pkgs.pkgsCross.aarch64-multiplatform;
        uboot-digilent-zybo = x86Pkgs.pkgsCross.armv7l-hf-multiplatform.callPackage ./digilent/zybo/uboot.nix {};
        sd-image-digilent-zybo =
          sdImageOf x86Pkgs "digilent-zybo"
          self.nixosConfigurations.digilent-zybo-example.config;
      };
    };

    # One entry per board, under the system that builds it. CI builds exactly
    # this set.
    checks = {
      aarch64-linux.terasic-de25-nano = self.packages.aarch64-linux.sd-image-terasic-de25-nano;
      x86_64-linux.digilent-zybo = self.packages.x86_64-linux.sd-image-digilent-zybo;
    };

    # `nix run .#update` from the repo root: runs the updateScript of every
    # package that has one, so a new board's kernel is picked up by adding it to
    # `packages`, with nothing to register here.
    apps = forToolSystems (tpkgs: let
      scripts =
        lib.mapAttrsToList (_: p: p.updateScript)
        (lib.filterAttrs (_: p: p ? updateScript) (lib.concatMapAttrs (_: ps: ps) self.packages));
      update = tpkgs.writeShellApplication {
        name = "update";
        runtimeInputs = with tpkgs; [git jq curl coreutils gnused gawk gnugrep];
        text = ''
          if [ ! -f flake.nix ] || [ ! -d terasic ]; then
            echo "run from the nixos-fpga repo root" >&2
            exit 1
          fi
          ${lib.concatMapStringsSep "\n" lib.escapeShellArgs scripts}
        '';
      };
    in {
      update = {
        type = "app";
        program = lib.getExe update;
      };
    });

    formatter = forToolSystems (tpkgs: tpkgs.alejandra);
  };
}
