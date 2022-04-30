{ pkgs, ... }:
{
  home.packages = with pkgs; [
    robo3t
  ];
}
