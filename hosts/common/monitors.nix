{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    htop
    nvtop
  ];
}
