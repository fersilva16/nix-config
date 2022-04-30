{ pkgs, ... }:
{
  users.users.fernando = {
    isNormalUser = true;

    shell = pkgs.fish;
    home = "/home/fernando";

    extraGroups = [
      "wheel"
      "networkmanager"
      "video"
      "docker"
    ];

    initialPassword = "password";
  };

  home-manager.users.fernando = _: {
    imports = [
      ./common/alacritty.nix
      ./common/autorandr.nix
      ./common/bat.nix
      ./common/bitwarden.nix
      ./common/bottom.nix
      ./common/broot.nix
      ./common/calibre.nix
      ./common/chromium.nix
      ./common/dconf.nix
      ./common/direnv.nix
      ./common/disable-keyboard.nix
      ./common/discord.nix
      ./common/doom-emacs/doom-emacs.nix
      ./common/exa.nix
      ./common/fd.nix
      # ./common/firefox.nix
      ./common/fish.nix
      ./common/flameshot.nix
      ./common/fzf.nix
      ./common/git.nix
      ./common/gpg.nix
      ./common/insomnia.nix
      ./common/kitty.nix
      ./common/mongodb.nix
      ./common/neofetch.nix
      ./common/neovim.nix
      ./common/nix.nix
      ./common/nyxt.nix
      ./common/obs.nix
      ./common/obsidian.nix
      ./common/peek.nix
      ./common/postman.nix
      # ./common/qutebrowser.nix
      ./common/ripgrep.nix
      ./common/rofi.nix
      ./common/slack.nix
      ./common/starship.nix
      ./common/vlc.nix
      ./common/vscode/vscode.nix
      ./common/wakatime.nix
      ./common/webstorm.nix
      ./common/xdg.nix
      ./common/xmobar/xmobar.nix
      ./common/xmonad/xmonad.nix
      ./common/ytmdesktop.nix
    ];
  };
}
