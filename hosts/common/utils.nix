{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    keyutils
    usbutils
    pciutils
    binutils
  ];
}
