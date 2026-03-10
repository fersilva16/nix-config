{ username, pkgs, ... }:
let
  jsonFormat = pkgs.formats.json { };
  inherit (pkgs) tmux-extras;
in
{
  home-manager.users.${username} = {
    programs.opencode = {
      enable = true;
      settings = {
        theme = "flexoki";
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
          notification = false;
          suppressWhenFocused = true;
          command = {
            enabled = true;
            path = "${tmux-extras}/bin/tmux-notify";
            args = [
              "add"
              "--event"
              "{event}"
              "{message}"
            ];
            minDuration = 0;
          };
        };
  };
}
