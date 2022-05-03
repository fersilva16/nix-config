{ pkgs, ... }:
{
  home.packages = with pkgs; [
    responsively
  ];
}
