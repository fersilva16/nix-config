{ inputs, config, pkgs, ... }: {
  imports = [
    inputs.doom-emacs.hmModule

    ./alacritty
    ./autorandr
    ./bat
    ./bottom
    ./broot
    ./chromium
    ./emacs
    ./exa
    ./firefox
    ./fish
    ./flameshot
    ./fzf
    ./git
    ./kitty
    ./rbw
    ./obs
    ./qutebrowser
    ./starship
    ./xmobar
    ./xmonad
  ];

  home.packages = with pkgs; [
    discord
    neofetch
    nyxt
    obsidian
    ytmdesktop
    any-nix-shell
    bottom
    vlc
    bitwarden-cli
    rofi
    jq
    slack
    robo3t
    ripgrep
  ];

  xdg.mimeApps = { enable = true; };

  home.file."home-config" = {
    target = ".config/nixpkgs";
    source = config.lib.file.mkOutOfStoreSymlink "/nix-config";
  };
}
