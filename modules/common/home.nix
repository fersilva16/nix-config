{ username, ... }:
let
  homeDirectory = "/Users/${username}";
in
{
  users.users.${username}.home = homeDirectory;

  home-manager.users.${username} = {
    home = {
      inherit homeDirectory username;

      stateVersion = "24.05";
    };
  };
}
