{ pkgs, ... }:
{
  home.packages = with pkgs; [
    syncthing
  ];
}
