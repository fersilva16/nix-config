{ pkgs, config, lib, ... }:
{
  imports = [
    ./common/homebrew.nix
    ./common/amie.nix
    ./common/ngrok.nix
  ];

  system.defaults = {
    trackpad = {
      Clicking = true;
      TrackpadThreeFingerDrag = true;
    };

    dock = {
      # Disable hot corner quick note
      wvous-br-corner = 1;

      # Disable rearrange of desktops
      mru-spaces = false;

      autohide = true;
      show-recents = false;
    };

    finder = {
      AppleShowAllExtensions = true;
      AppleShowAllFiles = true;
    };

    menuExtraClock = {
      ShowAMPM = true;
    };
  };

  environment = {
    systemPackages = [ pkgs.fish ];
    shells = [
      pkgs.fish
    ];
  };

  users.users.fernando = {
    shell = pkgs.fish;
    home = "/Users/fernando";
  };

  home-manager.users.fernando = {
    imports = [
      ./common/home.nix
      ./common/git.nix
      ./common/neovim.nix
      ./common/fish.nix
      ./common/eza.nix
      ./common/bat.nix
      ./common/starship.nix
      ./common/default-shell.nix
      ./common/paisa.nix
      ./common/direnv.nix
      ./common/ripgrep.nix
      ./common/circleci.nix
      ./common/cloud-nuke.nix
      ./common/kubectl.nix
      ./common/mongosh.nix
      ./common/ledger.nix
      ./common/flyctl.nix
      ./common/stern.nix
      ./common/awscli.nix
      ./common/wireguard.nix
    ];

    home.file.".gnupg/gpg-agent.conf" = {
      text = ''
        pinentry-program /usr/local/bin/pinentry-mac
      '';
    };
  };
}
