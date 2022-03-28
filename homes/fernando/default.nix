{ inputs, ... }:
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
}
