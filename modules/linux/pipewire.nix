# PipeWire audio with PulseAudio compat — also the screenshare transport
# for Wayland portals.
{ mkSystemModule, ... }:
mkSystemModule {
  name = "pipewire";
  config.services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };
}
