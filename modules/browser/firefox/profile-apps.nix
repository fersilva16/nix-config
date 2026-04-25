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
#
# Icon rendering: each bundle's icon is the Firefox shield re-tinted with
# per-profile theme colors. The original Firefox artwork (shield, fox curl,
# gradients, anti-aliased edges) is preserved exactly — we only swap colors.
#
# Pipeline (see `tintFirefoxIcon` below):
#   1. Convert firefox.icns to grayscale, preserving alpha.
#   2. Apply a sigmoidal-3 contrast curve so the original brightness range
#      (~0–78 % gray) stretches to use the full output range; without this
#      the brightest theme color is never reached and the fox silhouette
#      visually shrinks.
#   3. Build a 1×256 lookup-table gradient from the darker theme color to
#      the lighter one and remap the grayscale via ImageMagick `-clut`.
#
# CFBundleIconName is stripped from the cloned Info.plist so macOS loads our
# tinted firefox.icns instead of the AppIcon stored in Assets.car.
# Compositing uses pkgs.imagemagick referenced by nix store path (no system-
# wide install).
{ lib, pkgs }:
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
              themeBg = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                example = "#1B2540";
                description = ''
                  Background color used when tinting the Firefox shield.
                  Accepts any CSS color ImageMagick understands ("#RRGGBB",
                  "rgb(r,g,b)", "rgba(r,g,b,a)", named colors). When unset
                  (null), the bundle keeps the original Firefox icon.
                '';
              };
              themeFg = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                example = "#FF6B9D";
                description = ''
                  Foreground (accent) color used when tinting the Firefox
                  shield. Same accepted formats as themeBg. Set both
                  themeBg and themeFg to enable tinting.
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
        /Applications/<displayName>.app with a modified CFBundleIdentifier.
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
                ${lib.escapeShellArg (if profile.themeBg == null then "" else profile.themeBg)} \
                ${lib.escapeShellArg (if profile.themeFg == null then "" else profile.themeFg)}
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

            if [ ! -d "$SOURCE_APP" ]; then
              echo "[firefox] $SOURCE_APP not installed yet; skipping profile app build." >&2
              exit 0
            fi

            # Extract the largest PNG representation from an ICNS bundle.
            # Echoes the path to the extracted PNG on success, returns 1 on failure.
            # Caller is responsible for cleaning up the containing temp dir.
            extractLargestIcnsPng() {
              local icns="$1"
              local out_iconset="$2"
              /usr/bin/iconutil -c iconset "$icns" -o "$out_iconset" 2>/dev/null || return 1
              local candidate
              for candidate in icon_512x512@2x.png icon_512x512.png icon_256x256@2x.png icon_256x256.png icon_128x128@2x.png icon_128x128.png; do
                if [ -f "$out_iconset/$candidate" ]; then
                  printf '%s' "$out_iconset/$candidate"
                  return 0
                fi
              done
              return 1
            }

            # Compute approximate luminance (0–255) of a CSS-style color via
            # ImageMagick. Used to decide which of two theme colors maps to
            # "shield-dark" and which to "fox-light".
            colorLuminance() {
              local color="$1"
              ${pkgs.imagemagick}/bin/magick xc:"$color" -colorspace gray \
                -format "%[fx:int(mean*255)]" info: 2>/dev/null || echo "128"
            }

            # Re-tint a base ICNS with a 2-stop color gradient derived from the
            # profile's theme colors. Dark areas (the shield background) become
            # the darker theme color; bright areas (the orange fox) become the
            # lighter one. Output is a fresh multi-resolution ICNS file.
            tintFirefoxIcon() {
              local base_icns="$1"
              local theme_bg="$2"
              local theme_fg="$3"
              local output="$4"

              local tmp base_png
              tmp=$(/usr/bin/mktemp -d)

              base_png=$(extractLargestIcnsPng "$base_icns" "$tmp/base.iconset") || {
                echo "[firefox]   error: could not extract PNG from base icon $base_icns" >&2
                /bin/rm -rf "$tmp"
                return 1
              }

              # Pick the darker color for the shield background, the lighter
              # for the fox highlights — preserves Firefox's visual hierarchy
              # (dark backdrop, bright accent) regardless of whether the input
              # theme is "light" or "dark".
              local lum_bg lum_fg dark light
              lum_bg=$(colorLuminance "$theme_bg")
              lum_fg=$(colorLuminance "$theme_fg")
              if [ "$lum_bg" -lt "$lum_fg" ]; then
                dark="$theme_bg"
                light="$theme_fg"
              else
                dark="$theme_fg"
                light="$theme_bg"
              fi

              # Build a 1×256 vertical gradient (top=dark, bottom=light), then
              # use it as a CLUT mapping the grayscaled base to themed colors.
              # Pipeline:
              #   alpha = base.alpha
              #   gray  = base | -alpha off | -colorspace gray | -sigmoidal-contrast 3,50%
              #   tinted = gray | -clut <gradient(dark→light)>
              #   out    = tinted | composite(alpha) -compose CopyOpacity
              #
              # The sigmoidal-contrast S-curve pushes mid-tones toward their
              # respective ends (darks darker, brights brighter), expanding the
              # gray range the CLUT actually sees. Without it the fox highlights
              # cap at ~78 % gray (the brightest pixel in firefox.icns), so
              # the brightest CLUT color (themeFg) is never reached and the fox
              # silhouette visually shrinks vs the original. Strength 3 is mild
              # enough to keep gradients smooth.
              if ! ${pkgs.imagemagick}/bin/magick \
                     -size 1x256 "gradient:$dark-$light" "$tmp/clut.png" 2>/dev/null; then
                echo "[firefox]   error: imagemagick failed to build CLUT for theme ($dark → $light)" >&2
                /bin/rm -rf "$tmp"
                return 1
              fi
              ${pkgs.imagemagick}/bin/magick "$base_png" -alpha extract "$tmp/alpha.png" 2>/dev/null
              ${pkgs.imagemagick}/bin/magick "$base_png" -alpha off -colorspace gray -sigmoidal-contrast 3,50% "$tmp/gray.png" 2>/dev/null
              ${pkgs.imagemagick}/bin/magick "$tmp/gray.png" "$tmp/clut.png" -clut "$tmp/colored.png" 2>/dev/null
              if ! ${pkgs.imagemagick}/bin/magick "$tmp/colored.png" "$tmp/alpha.png" \
                     -alpha off -compose CopyOpacity -composite "$tmp/tinted.png" 2>/dev/null; then
                echo "[firefox]   error: imagemagick failed to apply tint" >&2
                /bin/rm -rf "$tmp"
                return 1
              fi

              # Package the tinted PNG as a multi-resolution ICNS.
              local out_iconset="$tmp/out.iconset" size
              /bin/mkdir -p "$out_iconset"
              for size in 16 32 128 256 512; do
                /usr/bin/sips -s format png -z "$size" "$size" "$tmp/tinted.png" \
                  --out "$out_iconset/icon_''${size}x''${size}.png" >/dev/null 2>&1 || true
                /usr/bin/sips -s format png -z "$((size * 2))" "$((size * 2))" "$tmp/tinted.png" \
                  --out "$out_iconset/icon_''${size}x''${size}@2x.png" >/dev/null 2>&1 || true
              done

              /usr/bin/iconutil -c icns "$out_iconset" -o "$output" 2>/dev/null
              local status=$?
              /bin/rm -rf "$tmp"
              return $status
            }

            createFirefoxProfileApp() {
              local display_name="$1"
              local profile_dir="$2"
              local bundle_id="$3"
              local theme_bg="$4"
              local theme_fg="$5"
              local target_app="/Applications/$display_name.app"
              local executable_name
              executable_name="firefox-$(printf '%s' "$display_name" | /usr/bin/tr '[:upper:] ' '[:lower:]-')"

              if [ ! -d "$PROFILES_DIR/$profile_dir" ]; then
                echo "[firefox] warning: profile directory missing: $PROFILES_DIR/$profile_dir" >&2
                echo "[firefox]          launching $display_name will create an empty profile there." >&2
              fi

              echo "[firefox] Building $target_app..."
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
              # macOS 11+ prefers CFBundleIconName (Assets.car AppIcon) over
              # CFBundleIconFile (firefox.icns). Drop it so our tinted icns wins.
              /usr/libexec/PlistBuddy -c "Delete :CFBundleIconName" "$plist" 2>/dev/null || true

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

              # Apply the theme tint when both colors are set; otherwise leave
              # the cloned firefox.icns untouched (default Firefox look). On
              # any tinting failure we just keep the default icon — the bundle
              # is still functional.
              if [ -n "$theme_bg" ] && [ -n "$theme_fg" ]; then
                if tintFirefoxIcon \
                     "$SOURCE_APP/Contents/Resources/firefox.icns" \
                     "$theme_bg" "$theme_fg" \
                     "$target_app/Contents/Resources/firefox.icns"; then
                  echo "[firefox]   icon: theme-tinted ($theme_bg → $theme_fg)"
                else
                  echo "[firefox]   theme tinting failed, keeping default Firefox icon" >&2
                fi
              else
                echo "[firefox]   icon: default Firefox (no theme set)"
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
