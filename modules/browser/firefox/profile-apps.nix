# Creates separate /Applications/<DisplayName>.app bundles per Firefox profile
# so each profile gets its own Cmd+Tab entry, Dock icon, and Launchpad tile.
#
# Firefox's new multi-process profile system launches each profile in its own
# OS process, but they all share the /Applications/Firefox.app bundle. macOS
# groups windows by CFBundleIdentifier for Cmd+Tab, which makes that app
# switcher behave unpredictably — sometimes hiding a profile's window entirely.
#
# Fix: clone Firefox.app per profile, rewrite its Info.plist with a unique
# CFBundleIdentifier / CFBundleName / CFBundleExecutable, swap in a launcher
# script that execs ./firefox with --no-remote --profile <path>, re-sign ad-hoc,
# and register with Launch Services.
#
# Default disabled so fresh installs don't build bundles pointing at profile
# directories that don't exist yet. Flip `profileApps.enable = true` after
# Firefox profiles are set up (manually or via backup restore).
{ lib }:
{
  default = false;

  extraOptions = {
    profiles = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, ... }:
          {
            options = {
              displayName = lib.mkOption {
                type = lib.types.str;
                default = "Firefox ${name}";
                description = ''
                  Display name for the profile's .app bundle. Becomes the filename
                  under /Applications/ and the Cmd+Tab label.
                '';
              };
              bundleId = lib.mkOption {
                type = lib.types.str;
                default = "org.mozilla.firefox.${name}";
                description = ''
                  Unique CFBundleIdentifier. Must differ from org.mozilla.firefox
                  so macOS treats this profile as a separate app in Cmd+Tab.
                '';
              };
              profileDir = lib.mkOption {
                type = lib.types.str;
                description = ''
                  Profile directory name under ~/Library/Application Support/Firefox/Profiles/.
                  Look it up via:
                    sqlite3 ~/Library/Application\ Support/Firefox/Profile\ Groups/*.sqlite \
                      "SELECT name, path FROM profiles;"
                '';
              };
              iconFile = lib.mkOption {
                type = lib.types.nullOr lib.types.path;
                default = null;
                description = ''
                  Optional path to a custom icon file (PNG or ICNS). When null,
                  the module auto-detects the profile's Firefox avatar from the
                  Profile Groups SQLite database and uses that. If no avatar is
                  found either, the default Firefox icon is kept.
                '';
              };
            };
          }
        )
      );
      default = { };
      description = ''
        Named Firefox profiles to get their own macOS .app bundles with unique
        Cmd+Tab entries. Each profile gets a full copy of Firefox.app at
        /Applications/<displayName>.app with a modified CFBundleIdentifier,
        rebuilt automatically whenever the base Firefox version changes.
      '';
    };

    hideBaseApp = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        When profile apps are enabled, run `chflags hidden` on /Applications/Firefox.app
        so the generic "Firefox" entry doesn't clutter Finder next to the
        profile-specific apps. Reversible with `chflags nohidden`.
      '';
    };
  };

  home =
    { cfg, lib, ... }:
    lib.mkIf (cfg.profiles != { }) {
      home.activation.firefoxProfileApps = {
        after = [ "writeBoundary" ];
        before = [ ];
        data =
          let
            mkProfileInvocation = profile: ''
              createFirefoxProfileApp \
                ${lib.escapeShellArg profile.displayName} \
                ${lib.escapeShellArg profile.profileDir} \
                ${lib.escapeShellArg profile.bundleId} \
                ${lib.escapeShellArg (if profile.iconFile == null then "" else toString profile.iconFile)}
            '';
            hideCmd = lib.optionalString cfg.hideBaseApp ''
              if [ -d "$SOURCE_APP" ]; then
                /usr/bin/chflags hidden "$SOURCE_APP" 2>/dev/null || true
              fi
            '';
          in
          ''
            set -euo pipefail

            SOURCE_APP="/Applications/Firefox.app"
            PROFILES_DIR="$HOME/Library/Application Support/Firefox/Profiles"
            PROFILE_GROUPS_DIR="$HOME/Library/Application Support/Firefox/Profile Groups"

            if [ ! -d "$SOURCE_APP" ]; then
              echo "[firefox] $SOURCE_APP not installed yet; skipping profile app build." >&2
              exit 0
            fi

            # Look up a profile's Firefox avatar image by querying every Profile Groups
            # SQLite database for the profile's path. Prints the full path to the avatar
            # PNG on success, returns 1 on miss.
            findProfileAvatar() {
              local profile_dir="$1"
              [ -d "$PROFILE_GROUPS_DIR" ] || return 1

              local db avatar_id=""
              for db in "$PROFILE_GROUPS_DIR"/*.sqlite; do
                [ -f "$db" ] || continue
                avatar_id=$(/usr/bin/sqlite3 "$db" \
                  "SELECT avatar FROM Profiles WHERE path='Profiles/$profile_dir' LIMIT 1;" \
                  2>/dev/null || echo "")
                [ -n "$avatar_id" ] && break
              done

              if [ -n "$avatar_id" ] && [ -f "$PROFILE_GROUPS_DIR/avatars/$avatar_id" ]; then
                printf '%s' "$PROFILE_GROUPS_DIR/avatars/$avatar_id"
                return 0
              fi
              return 1
            }

            # Convert an image (PNG or existing ICNS) to a multi-resolution ICNS file.
            convertToIcns() {
              local input="$1"
              local output="$2"

              # Already an ICNS? Just copy.
              if /usr/bin/file "$input" | /usr/bin/grep -qi "Mac OS X icon"; then
                /bin/cp "$input" "$output"
                return 0
              fi

              local tmp iconset size
              tmp=$(/usr/bin/mktemp -d)
              iconset="$tmp/icon.iconset"
              /bin/mkdir -p "$iconset"

              for size in 16 32 128 256 512; do
                /usr/bin/sips -s format png -z "$size" "$size" "$input" \
                  --out "$iconset/icon_''${size}x''${size}.png" >/dev/null 2>&1 || true
                /usr/bin/sips -s format png -z "$((size * 2))" "$((size * 2))" "$input" \
                  --out "$iconset/icon_''${size}x''${size}@2x.png" >/dev/null 2>&1 || true
              done

              /usr/bin/iconutil -c icns "$iconset" -o "$output" 2>/dev/null
              local status=$?
              /bin/rm -rf "$tmp"
              return $status
            }

            createFirefoxProfileApp() {
              local display_name="$1"
              local profile_dir="$2"
              local bundle_id="$3"
              local custom_icon="$4"
              local target_app="/Applications/$display_name.app"
              local executable_name
              executable_name="firefox-$(printf '%s' "$display_name" | /usr/bin/tr '[:upper:] ' '[:lower:]-')"

              local base_version
              base_version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$SOURCE_APP/Contents/Info.plist")
              local stored_version=""
              if [ -f "$target_app/Contents/Info.plist" ]; then
                stored_version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$target_app/Contents/Info.plist" 2>/dev/null || echo "")
              fi

              # Decide which icon we want and hash it so we also rebuild on icon changes.
              local desired_icon=""
              if [ -n "$custom_icon" ] && [ -f "$custom_icon" ]; then
                desired_icon="$custom_icon"
              elif avatar_path=$(findProfileAvatar "$profile_dir"); then
                desired_icon="$avatar_path"
              fi
              local desired_icon_hash=""
              if [ -n "$desired_icon" ]; then
                desired_icon_hash=$(/sbin/md5 -q "$desired_icon" 2>/dev/null || echo "")
              fi
              local stored_icon_hash=""
              if [ -f "$target_app/Contents/Resources/.profile-icon-hash" ]; then
                stored_icon_hash=$(/bin/cat "$target_app/Contents/Resources/.profile-icon-hash" 2>/dev/null || echo "")
              fi

              if [ -n "$stored_version" ] \
                 && [ "$base_version" = "$stored_version" ] \
                 && [ "$desired_icon_hash" = "$stored_icon_hash" ]; then
                echo "[firefox] $target_app up-to-date (v$base_version)."
                return 0
              fi

              if [ ! -d "$PROFILES_DIR/$profile_dir" ]; then
                echo "[firefox] warning: profile directory missing: $PROFILES_DIR/$profile_dir" >&2
                echo "[firefox]          launching $display_name will create an empty profile there." >&2
              fi

              echo "[firefox] Building $target_app (Firefox v$base_version)..."
              /bin/rm -rf "$target_app"
              /bin/cp -R "$SOURCE_APP" "$target_app"
              /usr/bin/xattr -cr "$target_app" 2>/dev/null || true

              local plist="$target_app/Contents/Info.plist"
              /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $bundle_id" "$plist"
              /usr/libexec/PlistBuddy -c "Set :CFBundleName $display_name" "$plist"
              if /usr/libexec/PlistBuddy -c "Print :CFBundleDisplayName" "$plist" >/dev/null 2>&1; then
                /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $display_name" "$plist"
              else
                /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string $display_name" "$plist"
              fi
              /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $executable_name" "$plist"
              /usr/libexec/PlistBuddy -c "Delete :SMPrivilegedExecutables" "$plist" 2>/dev/null || true

              local launcher="$target_app/Contents/MacOS/$executable_name"
              /bin/cat > "$launcher" <<LAUNCHER
            #!/bin/sh
            # Self-heal stale compatibility.ini.
            #
            # Firefox stamps \$PROFILE/compatibility.ini with the bundle path that
            # last opened the profile. If another Firefox (the base /Applications/Firefox.app
            # or the in-browser profile switcher from another bundle) has touched
            # this profile, our launch would silently exit because Firefox 137+
            # treats the path mismatch as a version/install downgrade. Detect the
            # mismatch up front, drop the stale compat, and launch with
            # --first-startup so Firefox re-stamps the file with OUR path.
            COMPAT="$PROFILES_DIR/$profile_dir/compatibility.ini"
            EXPECTED="LastPlatformDir=$target_app/Contents/Resources"
            if [ -f "\$COMPAT" ] && ! /usr/bin/grep -qxF "\$EXPECTED" "\$COMPAT"; then
              /bin/rm -f "\$COMPAT"
              exec "\$(dirname "\$0")/firefox" \\
                --no-remote \\
                --first-startup \\
                --profile "$PROFILES_DIR/$profile_dir" \\
                "\$@"
            fi

            exec "\$(dirname "\$0")/firefox" \\
              --no-remote \\
              --profile "$PROFILES_DIR/$profile_dir" \\
              "\$@"
            LAUNCHER
              /bin/chmod +x "$launcher"

              # Replace the bundle icon (firefox.icns) with the profile's avatar when available.
              if [ -n "$desired_icon" ]; then
                if convertToIcns "$desired_icon" "$target_app/Contents/Resources/firefox.icns"; then
                  echo "[firefox]   icon: $desired_icon"
                  printf '%s' "$desired_icon_hash" > "$target_app/Contents/Resources/.profile-icon-hash"
                else
                  echo "[firefox]   icon conversion failed, keeping default Firefox icon" >&2
                fi
              fi

              /bin/rm -rf "$target_app/Contents/_CodeSignature"
              /bin/rm -f  "$target_app/Contents/CodeResources"
              /bin/rm -f  "$target_app/Contents/embedded.provisionprofile"
              /bin/rm -rf "$target_app/Contents/MacOS/crashreporter.app"
              /bin/rm -rf "$target_app/Contents/MacOS/updater.app"
              /bin/rm -rf "$target_app/Contents/Library"
              /bin/rm -f  "$target_app/Contents/Resources/updater.ini"
              /bin/rm -f  "$target_app/Contents/Resources/update-settings.ini"

              /usr/bin/codesign --force --sign - --deep --identifier "$bundle_id" "$target_app" 2>/dev/null \
                || /usr/bin/codesign --force --sign - --deep "$target_app"

              /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$target_app" >/dev/null 2>&1 || true

              # Bump mtime so Finder/Dock invalidate their icon caches.
              /usr/bin/touch "$target_app"

              echo "[firefox] $target_app ready."
            }

            ${lib.concatMapStringsSep "\n" mkProfileInvocation (lib.attrValues cfg.profiles)}

            ${hideCmd}
          '';
      };
    };
}
