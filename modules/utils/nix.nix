{ pkgs, ... }:
{
  nix = {
    package = pkgs.nixUnstable;

    useDaemon = true;

    extraOptions = ''
      experimental-features = nix-command flakes
    '';
  };
}
