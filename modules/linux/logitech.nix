# Logitech Unifying/Bolt receiver support + solaar for pairing devices.
# Pairing is one-time and stored in the receiver itself; solaar mostly
# matters when adding a new device to the receiver.
{ mkSystemModule, ... }:
mkSystemModule {
  name = "logitech";
  config = {
    hardware.logitech.wireless = {
      enable = true;
      enableGraphical = true; # solaar
    };
  };
}
