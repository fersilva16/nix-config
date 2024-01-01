{ pkgs, ... }:
{
  home.packages = with pkgs; [
    paisa
  ];
}