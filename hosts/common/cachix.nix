{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    cachix
  ];

}
