{ username, pkgs, ... }:
{
  home-manager.users.${username} = {
    home.packages = with pkgs; [ temurin-bin-25 ];
  };
}
