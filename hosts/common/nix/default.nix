{ pkgs, ... }:
{
  nix = {
    package = pkgs.nixUnstable;

    settings = {
      trusted-users = [ "root" "@wheel" ];
      auto-optimise-store = true;
    };

    gc = {
      automatic = true;
      options = "--delete-older-than 15d";
    };

    extraOptions = ''
      experimental-features = nix-command flakes
    '';
  };
}
