{ pkgs, ... }:
{
  home.packages = with pkgs; [
    peek
    gifski
  ];
}
