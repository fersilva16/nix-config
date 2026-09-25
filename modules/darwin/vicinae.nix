{ mkUserModule, lib, ... }:
# Vicinae — open-source, Raycast-compatible launcher. Takes over ⌘Space; when
# Raycast is also enabled it moves Raycast to ⌥⌘Space so both can run side by side.
# settings.json is seeded once, not managed: Vicinae rewrites it from its GUI.
mkUserModule {
  name = "vicinae";
  system.homebrew.casks = [ "vicinae" ];
  home =
    { userCfg, ... }:
    {
      home.activation.vicinaeHotkey = {
        after = [ "writeBoundary" ];
        before = [ ];
        data = ''
          cfg="$HOME/.config/vicinae/settings.json"
          if [ ! -e "$cfg" ]; then
            mkdir -p "$(dirname "$cfg")"
            echo '{ "global_shortcuts": { "toggle": "cmd+space" } }' > "$cfg"
          fi
        ''
        + lib.optionalString userCfg.raycast.enable ''
          /usr/bin/defaults write com.raycast.macos raycastGlobalHotkey -string "Option-Command-49"
        '';
      };
    };
}
