# The smallest config that boots the original Zybo to a usable shell. Built by CI
# and published as `packages.x86_64-linux.sd-image-digilent-zybo`.
#
# Like nixpkgs' own installer images, it autologins `nixos` on the serial
# console with no password; add your key and drop the autologin before exposing
# the board to anything.
{
  networking.hostName = "zybo";
  image.baseName = "nixos-zybo";

  services.getty.autologinUser = "nixos";
  users.users.nixos = {
    isNormalUser = true;
    extraGroups = ["wheel"];
    initialHashedPassword = "";
  };
  security.sudo.wheelNeedsPassword = false;

  services.openssh.enable = true;

  # 2 cores and 512 MB: build elsewhere and copy closures over.
  nix.settings.max-jobs = 1;

  system.stateVersion = "26.05";
}
