# NVIDIA for NixOS hosts — polaris: RTX 5070 Ti (Blackwell).
#
# open = true is REQUIRED on Blackwell (the proprietary kmod does not
# support it) and is the upstream default for Turing+. Modesetting is
# required for Wayland. The old env-var workarounds (GBM_BACKEND,
# __GLX_VENDOR_LIBRARY_NAME, LIBVA_DRIVER_NAME) are obsolete with the
# open kmod and deliberately absent.
{ mkSystemModule, ... }:
mkSystemModule {
  name = "nvidia";
  config = {
    hardware.graphics = {
      enable = true;
      enable32Bit = true;
    };
    services.xserver.videoDrivers = [ "nvidia" ];
    hardware.nvidia = {
      open = true;
      modesetting.enable = true;
      nvidiaSettings = true;
    };
    boot.kernelParams = [
      "nvidia_drm.modeset=1"
      "nvidia_drm.fbdev=1"
    ];
  };
}
