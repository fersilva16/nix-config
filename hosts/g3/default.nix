{ inputs, pkgs, ... }:
let
  inherit (inputs.hardware.nixosModules) dell-g3-3779;
in
{
  imports = [
    dell-g3-3779

    ../common
    ../common/boot
    ../common/nix
    ../common/xmonad
    ../common/fonts

    ./audio
    ./fingerprint
    ./networking

    ./hardware-configuration.nix
  ];

  time.timeZone = "America/Sao_Paulo";

  i18n.defaultLocale = pkgs.lib.mkDefault "en_US.UTF-8";

  console = {
    earlySetup = true;
    keyMap = "br-abnt2";
  };

  hardware.bluetooth.enable = true;

  environment = {
    loginShellInit = ''
      [ -d "$HOME/.nix-profile" ] || /nix/var/nix/profiles/per-user/$USER/home-manager/activate &> /dev/null
    '';
    homeBinInPath = true;
    localBinInPath = true;
  };

  hardware.opengl.enable = true;

  # TODO: remove that later?
  hardware.bumblebee.enable = false;
}
