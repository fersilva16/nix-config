{ pkgs, ... }:
{
  home.packages = with pkgs; [
    cloud-nuke
  ];
}
