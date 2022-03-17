{ hardware, pkgs, ... }: {
  imports = [
    hardware.nixosModules.dell-g3-3779
  ];

  networking.hostName = "g3";

  nixpkgs.config.allowUnfree = true;

  nix = {
    package = pkgs.nixFlakes;
    gc = {
      automatic = true;
      options = "--delete-older-than 15d";
    };
    settings = {
      trusted-users = [ "root" "@wheel" ];
      auto-optimise-store = true;
    };
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
  };

  time.timeZone = "America/Sao_Paulo";

  i18n.defaultLocale = pkgs.lib.mkDefault "en_US.UTF-8";

  console = {
    earlySetup = true;
    keyMap = "br-abnt2";
  };

  sound.enable = true;
  hardware.bluetooth.enable = true;

  boot = {
    loader = {
      systemd-boot = {
        enable = true;
      };

      efi.canTouchEfiVariables = true;
    };
  };

  environment = {
    loginShellInit = ''
      [ -d "$HOME/.nix-profile" ] || /nix/var/nix/profiles/per-user/$USER/home-manager/activate &> /dev/null
    '';
    homeBinInPath = true;
    localBinInPath = true;
  };

  services.xserver = {
    enable = true;
    displayManager.startx.enable = true;
    windowManager.xmonad = {
      enable = true;
      enableContribAndExtras = true;
      extraPackages = haskellPackages: with haskellPackages; [
        xmonad
        xmonad-contrib
        xmonad-extras
        xmobar
      ];
    };
  };

  fonts = {
    enableDefaultFonts = true;
    fonts = with pkgs; [
      noto-fonts
      twitter-color-emoji
      fira-code
    ];
  };
}
