{ pkgs, ... }:
{
  home.packages = with pkgs; [
    flyctl
  ];
}
