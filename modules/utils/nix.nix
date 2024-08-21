{ pkgs, ... }:
{
  nix = {
    package = pkgs.nixVersions.git;

    useDaemon = true;

    extraOptions = ''
      experimental-features = nix-command flakes
    '';
  };
}
