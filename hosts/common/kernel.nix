{ pkgs, ... }:
{
  boot = {
    kernelPackages = pkgs.linuxPackages_5_18;
    # kernelParams = [ "quiet" ];
  };
}
