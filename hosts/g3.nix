{ hardware, pkgs, ... }: {
  imports = [
    hardware.nixosModules.dell-g3-3779
  ];

  networking = {
    hostName = "g3";

    useDHCP = false;
  };

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

    initrd = {
      # TODO: change availableKernelModules
      availableKernelModules = [
        "ata_piix"
        "ohci_pci"
        "sd_mod"
        "sr_mod"
      ];

      # TODO: change kernelModules
      kernelModules = ["dm-snapshot"];

      luks.devices."lvm" = {
        # TODO: change device
        device = "/dev/disk/by-label/lvm";
        preLVM = true;
        allowDiscards = true;
      };
    };

    resumeDevice = "/swapfile";
  };

  swapDevices = [
    {
      device = "/swapfile";
      size = 6144;
    }
  ];

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

  # TODO: change filesystems
  fileSystems."/" = {
    device = "/dev/disk/by-label/lvm";
    fsType = "btrfs";
    options = ["subvol=root"];
  };

  fileSystems."/home" = {
    device = "/dev/disk/by-label/lvm";
    fsType = "btrfs";
    options = ["subvol=home"];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/boot";
    fsType = "vfat";
  };
}
