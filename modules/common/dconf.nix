{ pkgs, ... }:
{
  home.packages = with pkgs; [
    dconf
  ];
}
