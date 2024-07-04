{ pkgs, ... }@args:
let
  mkUserImports = import ../../lib/mkUserImports.nix args;

  username = "fernando";
in
{
  imports = mkUserImports username [
    ../common/amie.nix
    ../common/arc.nix
    ../common/ngrok.nix
    ../common/home.nix
    ../common/homebrew.nix
    ../common/git.nix
    ../common/fish.nix
    ../common/bitwarden.nix
    ../common/eza.nix
    ../common/bat.nix
    ../common/starship.nix
    ../common/paisa.nix
    ../common/direnv.nix
    ../common/ripgrep.nix
    ../common/mongosh.nix
    ../common/ledger.nix
    ../common/flyctl.nix
    ../common/stern.nix
    ../common/awscli.nix
    ../common/wireguard.nix
    ../common/gpg.nix
    ../common/obsidian.nix
    ../common/whatsapp.nix
    ../common/raycast.nix
    ../common/zoom.nix
    ../common/dbeaver.nix
    ../common/selfcontrol.nix
    ../common/studio-3t.nix
    ../common/postman.nix
    ../common/iina.nix
    ../common/warp.nix
    ../common/calibre.nix
    ../common/orbstack.nix
    ../darwin/pinentry-mac.nix
    ../common/slack.nix
    ../common/vscode/vscode.nix
    ../common/discord.nix
  ];
}
