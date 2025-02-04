{ pkgs, ... }:
{
  nix = {
    package = pkgs.nixVersions.latest;

    useDaemon = true;

    extraOptions = ''
      experimental-features = nix-command flakes
    '';
  };
}
