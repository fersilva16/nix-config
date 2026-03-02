{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [ pkg-config ];
}
