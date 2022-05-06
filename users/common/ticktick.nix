{ pkgs, ... }:
{
  home.packages = with pkgs; [
    ticktick
  ];
}
