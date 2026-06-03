# OpenLogi — local-first, open-source alternative to Logitech Options+ for
# remapping HID++ devices. Shipped in the official homebrew/homebrew-cask, so
# no custom tap is needed. Quit Logi Options+ before launching: the two fight
# over HID++ receiver access. First launch needs Accessibility / Input
# Monitoring permissions to drive the OS event tap.
{ mkUserModule, ... }:
mkUserModule {
  name = "openlogi";
  system.homebrew.casks = [ "openlogi" ];
}
