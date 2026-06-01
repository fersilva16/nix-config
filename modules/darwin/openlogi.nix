# OpenLogi — open-source Logi Options+ alternative for remapping Logitech
# devices via HID++. Distributed through the maintainer's own tap
# (aprilnea/homebrew-tap), wired in modules/system/homebrew.nix.
{ mkUserModule, ... }:
mkUserModule {
  name = "openlogi";
  system.homebrew.casks = [ "aprilnea/tap/openlogi" ];
}
