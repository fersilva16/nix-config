{ username, pkgs, ... }:
{
  home-manager.users.${username} = {
    home.packages = with pkgs; [
      bitwarden-cli
    ];
  };
}
