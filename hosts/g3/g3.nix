{ inputs, pkgs, ... }:
let
  inherit (inputs.hardware.nixosModules) dell-g3-3779;
in
{
  imports = [
    dell-g3-3779

    ../common/common.nix
    ../common/boot.nix
    ../common/docker.nix
    ../common/nix.nix
    ../common/xserver.nix
    ../common/fonts.nix
    ../common/ssh.nix
    ../common/gnupg.nix

    ./audio.nix
    ./fingerprint.nix
    ./networking.nix
    ./nvidia.nix

    ./hardware-configuration.nix
  ];

  environment.systemPackages = with pkgs; [
    keyutils
    usbutils
    pciutils
    lm_sensors
    light
    htop
    nvtop
    zip
    unzip

    cachix
  ];

  time.hardwareClockInLocalTime = true;

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
