{ pkgs, ... }@args:
let
  mkUserImports = import ../../lib/mkUserImports.nix args;

  username = "fernando";
in {
  imports = mkUserImports username [
    ../common/ngrok.nix
    ../common/home.nix
    ../common/homebrew.nix
    ../common/git.nix
    ../common/fish.nix
    ../common/eza.nix
    ../common/bat.nix
    ../common/starship.nix
    ../common/direnv.nix
    ../common/ripgrep.nix
    ../common/mongosh.nix
    ../common/flyctl.nix
    ../common/stern.nix
    ../common/awscli.nix
    ../common/wireguard.nix
    ../common/obsidian.nix
    ../common/whatsapp.nix
    ../common/raycast.nix
    ../common/dbeaver.nix
    ../common/selfcontrol.nix
    ../common/studio-3t.nix
    ../common/postman.nix
    ../common/iina.nix
    ../common/calibre.nix
    ../common/orbstack.nix
    ../common/vscode/vscode.nix
    ../common/discord.nix
    ../browser/firefox.nix
    ../browser/chrome.nix
    ../cli/tmux.nix
    ../cli/nvim.nix
    ../terminal/kitty.nix
    ../common/word.nix
    ../security/1password.nix
    ../chat/slack.nix
    ../browser/zen.nix
    ../common/libreoffice.nix
    ../common/netnewswire.nix
    ../common/figma.nix
    ../games/sony.nix
    ../common/anki.nix
    ../ledger/paisa.nix
    ../ledger/ledger.nix
    ../common/notion-calendar.nix
    ../cli/minikube.nix
    ../common/keyboardcleantool.nix
    ../common/anytype.nix
    ../editor/intellij.nix
    ../chat/teams.nix
  ];
}
