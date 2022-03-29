{ inputs, config, ... }:
{
  imports = [
    inputs.doom-emacs.hmModule

    ./alacritty
    ./bat
    ./bottom
    ./broot
    ./chromium
    ./discord
    ./emacs
    ./exa
    ./firefox
    ./fish
    ./flameshot
    ./fzf
    ./git
    ./nyxt
    ./obs
    ./obsidian
    ./qutebrowser
    ./starship
    ./xmobar
    ./xmonad
    ./ytmdesktop
  ];

  home.file."home-config" = {
    target = ".config/nixpkgs";
    source = config.lib.file.mkOutOfStoreSymlink "/nix-config";
  };
}
