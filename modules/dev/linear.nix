{ username, ... }:
{
  homebrew.casks = [ "linear-linear" ];
  homebrew.brews = [ "linear" ];

  home-manager.users.${username} = {
    xdg.configFile."linear/linear.toml".text = ''
      team_id = "ENG"
      issue_sort = "priority"
    '';
  };
}
