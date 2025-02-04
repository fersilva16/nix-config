{ username, pkgs, ... }:
{
  home-manager.users.${username} = {
    home.packages = with pkgs; [ ripgrep ];
  };
}
