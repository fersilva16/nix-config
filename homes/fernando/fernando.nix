{ inputs, config, pkgs, ... }:
{
  imports = [
    ./alacritty.nix
    ./autorandr.nix
    ./bat.nix
    ./bottom.nix
    ./broot.nix
    ./chromium.nix
    ./emacs/emacs.nix
    ./exa.nix
    # ./firefox.nix
    ./fish.nix
    ./flameshot.nix
    ./fzf.nix
    ./git.nix
    ./kitty.nix
    ./rbw.nix
    ./obs.nix
    # ./qutebrowser.nix
    ./starship.nix
    ./xmobar/xmobar.nix
    ./xmonad/xmonad.nix
    ./vscode/vscode.nix
    ./xdg.nix
    ./direnv.nix
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
    ripgrep
    gh

    jetbrains.webstorm
    neovim

    robo3t

    insomnia

    wakatime

    rnix-lsp

    calibre
  ];

  home.keyboard = null;
}
