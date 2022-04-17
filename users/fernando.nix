{ pkgs, ... }:
{
  users.users.fernando = {
    isNormalUser = true;

    shell = pkgs.fish;
    home = "/home/fernando";

    extraGroups = [
      "wheel"
      "networkmanager"
      "video"
      "docker"
    ];

    # TODO: change the password
    initialPassword = "password";
  };

  home-manager.users.fernando = import ../homes/fernando/fernando.nix;
}
