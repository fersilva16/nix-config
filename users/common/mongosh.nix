{ pkgs, ... }:
{
  home.packages = with pkgs; [
    mongosh
    mongodb-tools
  ];
}
