# Bluetooth + blueman applet (WM-only desktop, no DE bluetooth UI).
# Note: polaris' RTL8922AE has rough BT/WiFi coexistence — if WiFi drops,
# test with BT off before blaming the driver.
{ mkSystemModule, ... }:
mkSystemModule {
  name = "bluetooth";
  config = {
    hardware.bluetooth = {
      enable = true;
      powerOnBoot = true;
    };
    services.blueman.enable = true;
  };
}
