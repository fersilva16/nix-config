{ mkUserModule, lib, ... }:
# Vicinae — open-source, Raycast-compatible launcher. Takes over ⌘Space; when
# Raycast is also enabled it moves Raycast to ⌥⌘Space so both can run side by side.
# settings.json is seeded once, not managed: Vicinae rewrites it from its GUI.
mkUserModule {
  name = "vicinae";
  system = {
    homebrew.casks = [ "vicinae" ];
    # Vicinae unpacks extension-manager.js into $TMPDIR/vicinae only at launch, and
    # macOS dirhelper (daily 03:35) deletes $TMPDIR files older than 3 days, which
    # crashes the extension manager for good ("Extension manager is not running").
    # Keep the files fresh until upstream re-extracts or moves them.
    launchd.user.agents.vicinae-tmp-keepalive = {
      script = ''
        d="$(/usr/bin/getconf DARWIN_USER_TEMP_DIR)vicinae"
        [ -d "$d" ] && /usr/bin/find "$d" -type f -exec /usr/bin/touch {} +
        exit 0
      '';
      serviceConfig = {
        RunAtLoad = true;
        StartInterval = 6 * 60 * 60;
      };
    };
  };
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
