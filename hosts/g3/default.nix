{ inputs, pkgs, ... }:
let
  inherit (inputs.hardware.nixosModules) dell-g3-3779;
in
{
  imports = [
    dell-g3-3779

    ../common
    ../common/boot
    ../common/docker
    ../common/nix
    ../common/xserver
    ../common/fonts

    ./audio
    ./fingerprint
    ./networking
    ./nvidia

    ./hardware-configuration.nix
  ];

  environment.systemPackages = with pkgs; [
    usbutils
    pciutils
    light
    htop
    nvtop
  ];

  time.timeZone = "America/Sao_Paulo";

  i18n.defaultLocale = pkgs.lib.mkDefault "en_US.UTF-8";

  console = {
    earlySetup = true;
    keyMap = "br-abnt2";
  };

  hardware.bluetooth.enable = true;

  services.xserver.displayManager.autoLogin = {
    enable = true;
    user = "fernando";
  };

  hardware.opengl.enable = true;
}
