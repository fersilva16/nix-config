{ pkgs, ... }:
{
  home.packages = with pkgs; [
    bookcut
  ];
}
