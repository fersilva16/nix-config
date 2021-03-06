{ lib, ... }:
{
  boot.initrd.kernelModules = [
    "nvidia"
    "nvidia_modeset"
    "nvidia_uvm"
    "nvidia_drm"
  ];

  boot.kernelParams = [ "nvidia-drm.modeset=1" ];

  hardware.nvidia.modesetting.enable = true;
  hardware.nvidia.prime = {
    offload.enable = lib.mkForce false;
    sync.enable = true;

    nvidiaBusId = "PCI:1:0:0";

    intelBusId = "PCI:0:2:0";
  };

  services.xserver = {
    videoDrivers = lib.mkForce [ "nvidia" ];

    # screenSection = ''
    #   Option         "metamodes" "nvidia-auto-select +0+0 {ForceFullCompositionPipeline=On}"
    #   Option         "AllowIndirectGLXProtocol" "off"
    #   Option         "TripleBuffer" "on"
    # '';
  };
}
