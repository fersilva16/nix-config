{ pkgs, config, ... }:
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

  security.sudo = {
    extraRules = [
      {
        runAs = "root";
        users = [ "fernando" ];
        commands = [
          {
            command = "${config.system.build.nixos-rebuild}/bin/nixos-rebuild switch";
            options = [ "NOPASSWD" ];
          }
          {
            command = "${config.system.build.nixos-rebuild}/bin/nixos-rebuild switch --show-trace";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];
  };

  home-manager.users.root = {
    imports = [
      ./common/home.nix
    ];
  };

  home-manager.users.fernando = {
    imports = [
      ./common/alacritty.nix
      ./common/android.nix
      ./common/autorandr.nix
      ./common/bat.nix
      ./common/bitwarden.nix
      ./common/bottom.nix
      ./common/broot.nix
      ./common/bun.nix
      ./common/calibre.nix
      ./common/chromium.nix
      ./common/circleci.nix
      ./common/colors.nix
      ./common/dbeaver.nix
      ./common/dconf.nix
      ./common/direnv.nix
      ./common/discord.nix
      ./common/dunst.nix
      # ./common/doom-emacs/doom-emacs.nix
      ./common/emacs/emacs.nix
      ./common/exa.nix
      ./common/fd.nix
      ./common/feh.nix
      # ./common/firefox.nix
      ./common/fish.nix
      ./common/flameshot.nix
      ./common/fzf.nix
      ./common/git.nix
      ./common/glab.nix
      ./common/gpg.nix
      ./common/home.nix
      ./common/insomnia.nix
      ./common/kitty.nix
      # ./common/krita.nix
      ./common/krusader.nix
      ./common/minecraft.nix
      ./common/mongodb.nix
      ./common/neofetch.nix
      ./common/neovim.nix
      ./common/nix.nix
      ./common/nyxt.nix
      ./common/obs.nix
      ./common/peek.nix
      ./common/postman.nix
      # ./common/qutebrowser.nix
      ./common/responsively.nix
      ./common/ripgrep.nix
      ./common/rofi.nix
      ./common/rust.nix
      ./common/slack.nix
      ./common/starship.nix
      ./common/vlc.nix
      ./common/vscode/vscode.nix
      ./common/wakatime.nix
      ./common/wallpaper/wallpaper.nix
      ./common/xdg.nix
      ./common/xmobar/xmobar.nix
      ./common/xmonad/xmonad.nix
      ./common/ytmdesktop/ytmdesktop.nix
    ];
  };
}
