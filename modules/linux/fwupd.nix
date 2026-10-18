# Firmware updates from LVFS — polaris: Samsung 980 Pro NVMe and the
# motherboard UEFI. fwupd only refreshes metadata and lists what is
# available; nothing is flashed until `fwupdmgr update` is run by hand.
{ mkSystemModule, ... }:
mkSystemModule {
  name = "fwupd";
  config.services.fwupd.enable = true;
}
