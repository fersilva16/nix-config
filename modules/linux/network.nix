# NetworkManager + redistributable firmware (WiFi/BT chips need it —
# polaris: Realtek RTL8922AE).
{ mkSystemModule, ... }:
mkSystemModule {
  name = "network";
  config = {
    networking.networkmanager.enable = true;
    hardware.enableRedistributableFirmware = true;
  };
}
