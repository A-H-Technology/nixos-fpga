{
  description = "NixOS hardware support for FPGA and SoC-FPGA boards";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = {
    self,
    nixpkgs,
  }: let
    inherit (nixpkgs) lib;

    # Every board here is an ARM SoC, and its kernel and image build natively on
    # aarch64 (CI uses GitHub's ARM runners). Tooling runs anywhere.
    boardSystem = "aarch64-linux";
    toolSystems = ["x86_64-linux" "aarch64-linux"];
    forToolSystems = f: lib.genAttrs toolSystems (s: f nixpkgs.legacyPackages.${s});

    pkgs = nixpkgs.legacyPackages.${boardSystem};

    example = name: modules:
      lib.nixosSystem {
        modules = modules ++ [./examples/${name}.nix {nixpkgs.hostPlatform = boardSystem;}];
      };
  in {
    nixosModules = {
      terasic-de25-nano = ./terasic/de25-nano;
      terasic-de25-nano-sd-image = ./terasic/de25-nano/sd-image.nix;
    };

    overlays.default = final: _prev: {
      linux-terasic-de25-nano = final.callPackage ./terasic/de25-nano/kernel {};
      linuxPackages-terasic-de25-nano = final.linuxPackagesFor final.linux-terasic-de25-nano;
      uboot-terasic-de25-nano-stock = final.callPackage ./terasic/de25-nano/uboot-stock.nix {};
    };

    nixosConfigurations.terasic-de25-nano-example = example "terasic-de25-nano" [
      self.nixosModules.terasic-de25-nano
      self.nixosModules.terasic-de25-nano-sd-image
    ];

    packages.${boardSystem} = let
      overlaid = self.overlays.default pkgs pkgs;
    in {
      inherit (overlaid) linux-terasic-de25-nano uboot-terasic-de25-nano-stock;
      sd-image-terasic-de25-nano = let
        inherit (self.nixosConfigurations.terasic-de25-nano-example.config.system.build) sdImage;
      in
        pkgs.runCommand "sd-image-terasic-de25-nano" {} ''
          cp ${sdImage}/sd-image/*.img $out
        '';
    };

    # One entry per board; CI builds exactly this set.
    checks.${boardSystem} = {
      terasic-de25-nano = self.packages.${boardSystem}.sd-image-terasic-de25-nano;
    };

    # `nix run .#update` from the repo root: runs the updateScript of every
    # package that has one, so a new board's kernel is picked up by adding it to
    # `packages`, with nothing to register here.
    apps = forToolSystems (tpkgs: let
      scripts =
        lib.mapAttrsToList (_: p: p.updateScript)
        (lib.filterAttrs (_: p: p ? updateScript) self.packages.${boardSystem});
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
