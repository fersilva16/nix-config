{ inputs, ... }:
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
    ./fzf
    ./git
    ./nyxt
    ./obs
    ./obsidian
    ./qutebrowser
    ./starship
    ./xmonad
    ./ytmdesktop
  ];
}
