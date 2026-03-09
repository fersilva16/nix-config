{ username, pkgs, ... }:
let
  jsonFormat = pkgs.formats.json { };
in
{
  home-manager.users.${username} = {
    programs.opencode = {
      enable = true;
      settings = {
        plugin = [
          "@simonwjackson/opencode-direnv"
          "@mohak34/opencode-notifier@latest"
        ];
        permission = {
          external_directory = "allow";
        };
      };
    };

    xdg.configFile."opencode/opencode-notifier.json".source =
      jsonFormat.generate "opencode-notifier.json"
        {
          sound = true;
          notification = true;
          suppressWhenFocused = true;
        };
  };
}
