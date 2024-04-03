{ pkgs, ... }:
{
  home.packages = with pkgs; [
    stern
  ];
}
