{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    gcc
  ];
}
