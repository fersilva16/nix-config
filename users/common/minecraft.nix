{ pkgs, ... }:
{
  home.packages = with pkgs; [
    tlauncher
    ferium
  ];
}
