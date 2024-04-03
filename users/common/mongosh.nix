{ pkgs, ... }:
{
  home.packages = with pkgs; [
    mongosh
  ];
}
