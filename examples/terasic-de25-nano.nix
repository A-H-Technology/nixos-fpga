# The smallest config that boots the DE25-Nano to a usable shell. Built by CI and
# published as `packages.aarch64-linux.sd-image-terasic-de25-nano`.
#
# Like nixpkgs' own installer images, it autologins `nixos` on the serial
# console with no password; add your key and drop the autologin before exposing
# the board to anything.
{
  networking.hostName = "de25-nano";
  image.baseName = "nixos-de25-nano";

  services.getty.autologinUser = "nixos";
  users.users.nixos = {
    isNormalUser = true;
    extraGroups = ["wheel"];
    initialHashedPassword = "";
  };
  security.sudo.wheelNeedsPassword = false;

  services.openssh.enable = true;

  # 4 cores and ~957 MB: build elsewhere and copy closures over.
  nix.settings.max-jobs = 1;

  system.stateVersion = "26.05";
}
