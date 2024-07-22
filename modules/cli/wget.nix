{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    wget
  ];
}
