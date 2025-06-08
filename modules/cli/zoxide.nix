{ username, pkgs, ... }:
{
  home-manager.users.${username} = {
    programs.zoxide = {
      enable = true;

      enableFishIntegration = true;

      options = [
        "--cmd=cd"
      ];
    };
  };
}
