{
  mkUserModule,
  forPlatform,
  pkgs,
  lib,
  ...
}:
# Vicinae — open-source, Raycast-compatible launcher.
#
# darwin: Homebrew cask. Takes over ⌘Space; when Raycast is also enabled it
# moves Raycast to ⌥⌘Space so both can run side by side. settings.json is
# seeded once, not managed: Vicinae rewrites it from its GUI.
#
# linux: home-manager's programs.vicinae with its systemd server. Wayland has
# no global-shortcut API Vicinae can use, so the compositor owns the hotkey:
# under niri, Super+Space (Cmd+Space) toggles Vicinae instead of noctalia's
# launcher.
mkUserModule {
  name = "vicinae";
  system = forPlatform {
    darwin = {
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
  };
  home =
    { userCfg, ... }:
    let
      # A window outline with the target half filled in.
      snapIcon =
        side:
        builtins.toFile "${side}-half.svg" ''
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
            <rect width="64" height="64" rx="14" fill="#3B82F6"/>
            <rect x="12" y="16" width="40" height="32" rx="4" fill="none" stroke="#fff" stroke-width="4"/>
            <rect x="${if side == "left" then "12" else "32"}" y="16" width="20" height="32" fill="#fff"/>
          </svg>
        '';
      snapScript = side: title: {
        executable = true;
        text = ''
          #!/bin/sh
          # @vicinae.schemaVersion 1
          # @vicinae.title ${title}
          # @vicinae.mode silent
          # @vicinae.icon ${snapIcon side}
          # @vicinae.keywords ["snap", "window", "tile"]
          exec /usr/bin/open -g "hammerspoon://snap?side=${side}"
        '';
      };

      # Included last in niri's config.kdl: niri includes are positional and
      # their binds override earlier ones, so this replaces noctalia's
      # launcher bind without touching the niri module. Super, not Mod: niri's
      # Mod is Hyper, and Hyper+Space is xremap's terminal toggle.
      niriBinds = pkgs.writeText "vicinae-niri.kdl" ''
        binds {
            Super+Space { spawn "${lib.getExe' pkgs.vicinae "vicinae"}" "toggle"; }
        }
      '';

      # Nix-owned settings live in nix.json, which Vicinae only reads; this
      # makes the GUI-written settings.json import it (seeding it if absent).
      importNixJson = awk: seed: ''
        cfg="$HOME/.config/vicinae/settings.json"
        if [ ! -e "$cfg" ]; then
          mkdir -p "$(dirname "$cfg")"
          echo '${seed}' > "$cfg"
        elif ! grep -q '"imports"' "$cfg"; then
          ${awk} '!done && sub(/[{]/, "{ \"imports\": [ \"./nix.json\" ],") { done = 1 } 1' "$cfg" > "$cfg.tmp"
          mv "$cfg.tmp" "$cfg"
        elif ! grep -q 'nix\.json' "$cfg"; then
          echo "vicinae: settings.json has its own imports; add \"./nix.json\" to them by hand" >&2
        fi
      '';
    in
    forPlatform {
      darwin = {
        # Nix-owned settings live in an imported file Vicinae only reads; settings.json
        # (GUI-written) still wins on conflict. Vicinae keeps `imports` when it rewrites.
        home.file = {
          ".config/vicinae/nix.json".text = builtins.toJSON {
            providers.applications.entrypoints."com.apple.PhotoBooth".alias = "camera";
          };

          # "Left Half" / "Right Half" script commands; Hammerspoon does the move
          # through the hammerspoon://snap handler in vicinae-snap.lua.
          ".hammerspoon/extras/vicinae-snap.lua" = lib.mkIf userCfg.hammerspoon.enable {
            source = ./vicinae-snap.lua;
          };
          ".local/share/vicinae/scripts/left-half.sh" = lib.mkIf userCfg.hammerspoon.enable (
            snapScript "left" "Left Half"
          );
          ".local/share/vicinae/scripts/right-half.sh" = lib.mkIf userCfg.hammerspoon.enable (
            snapScript "right" "Right Half"
          );
        };

        home.activation.vicinaeHotkey = {
          after = [ "writeBoundary" ];
          before = [ ];
          data =
            importNixJson "/usr/bin/awk" ''{ "imports": [ "./nix.json" ], "global_shortcuts": { "toggle": "cmd+space" } }''
            + lib.optionalString userCfg.raycast.enable ''
              /usr/bin/defaults write com.raycast.macos raycastGlobalHotkey -string "Option-Command-49"
            '';
        };
      };

      linux = {
        programs.vicinae = {
          enable = true;
          systemd.enable = true;
        };

        xdg.configFile = {
          # Launch apps in their own transient scope. Otherwise they stay in
          # vicinae.service's cgroup: billed to it, and killed or orphaned
          # with it (a vicinae crash once took Steam along).
          "vicinae/nix.json".text = builtins.toJSON {
            providers.applications.preferences.launchPrefix = "${pkgs.systemd}/bin/systemd-run --user --scope --collect --";
          };
          "niri/config.kdl" = lib.mkIf userCfg.niri.enable {
            text = lib.mkAfter ''
              include "${niriBinds}"
            '';
          };
        };

        home.activation.vicinaeImports = {
          after = [ "writeBoundary" ];
          before = [ ];
          data = importNixJson "${pkgs.gawk}/bin/awk" ''{ "imports": [ "./nix.json" ] }'';
        };
      };
    };
}
