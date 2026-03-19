{ username, pkgs, ... }:
{
  homebrew.casks = [ "linear-linear" ];

  home-manager.users.${username} = {
    home.packages = with pkgs; [
      linear-cli
      gum
      jq
    ];
  };
}
