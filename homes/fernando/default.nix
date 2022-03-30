{ inputs, config, pkgs, ... }:
{
  imports = [
    inputs.doom-emacs.hmModule

    ./alacritty
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
  ];

  xdg.mimeApps = {
    enable = true;
  };

  home.file."home-config" = {
    target = ".config/nixpkgs";
    source = config.lib.file.mkOutOfStoreSymlink "/nix-config";
  };
}
