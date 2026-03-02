{ username, pkgs, ... }:
let
  configDir = ".config/karabiner";
in
{
  homebrew.casks = [ "karabiner-elements" ];

  home-manager.users.${username} = {
    home.file."${configDir}/karabiner.json" = {
      source = ./karabiner.json;
      force = true;
    };
  };
}
