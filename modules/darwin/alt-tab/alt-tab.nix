{ mkUserModule, ... }:
# AltTab — window-based, monitor-aware cmd+tab replacement (Pro).
#
# Behavioral settings are captured from the GUI as strings (AltTab stores most
# prefs as strings, even bools/ints) — matching the on-disk plist exactly.
#
# The two ⌘ shortcuts (holdShortcut / holdShortcut2) are NSKeyedArchiver binary
# blobs. nixpkgs lacks lib.mkPlistData and CustomUserPreferences can't emit a
# <data> value, so the raw blob lives in ./holdShortcut.bin and the activation
# script writes it via `defaults write` (cfprefsd-safe) as an old-style plist
# value (hex). The blob encodes ⌘ and is identical for both slots.
#
# ponytail: deliberate brittle shortcut — the blob is opaque and tied to
# AltTab's archive format. Re-capture the bytes if a future AltTab rejects it:
#   defaults export com.lwouis.alt-tab-macos /tmp/at.plist
#   python3 -c "import plistlib;open('holdShortcut.bin','wb').write(
#     plistlib.load(open('/tmp/at.plist','rb'))['holdShortcut']['secureData'])"
# Upgrade path: lib.mkPlistData once nixpkgs ships it.
# (Not managed: telemetry MSAppCenter*, window positions, Sparkle.)
#
# After a rebuild, restart AltTab. Editing these in the GUI is overridden on the
# next rebuild — change them here.
mkUserModule {
  name = "alt-tab";
  system = {
    homebrew.casks = [ "alt-tab" ];

    system.defaults.CustomUserPreferences."com.lwouis.alt-tab-macos" = {
      # Appearance
      appearanceSize = "0";
      appearanceStyle = "1";
      appearanceTheme = "2";
      hideColoredCircles = "false";
      hideSpaceNumberLabels = "false";
      menubarIconShown = "false";
      shortcutStyle = "0";

      # Behavior
      captureWindowsInBackground = "false";
      previewFocusedWindow = "false";
      nextWindowGesture = "3";
      mouseHoverEnabled = "true";
      cursorFollowFocus = "0";
      showOnScreen = "1";

      # Shortcut 1 — which windows it shows
      appsToShow = "0";
      screensToShow = "1"; # 1 = active screen only

      # Shortcut 2 — per-shortcut filters (the "10" suffix is AltTab's second slot)
      appsToShow10 = "0";
      screensToShow10 = "1";
    };
  };

  # Write the two ⌘ shortcut blobs as the user, after HM has written its files.
  # Read the raw blob from ./holdShortcut.bin, hex-encode it, and `defaults write`
  # the nested { secureData = <data>; string = "⌘"; } dict (cfprefsd-safe).
  home.home.activation.altTabShortcuts = {
    after = [ "writeBoundary" ];
    before = [ ];
    data = ''
      hex=$(/usr/bin/xxd -p ${./holdShortcut.bin} | /usr/bin/tr -d '\n')
      for key in holdShortcut holdShortcut2; do
        /usr/bin/defaults write com.lwouis.alt-tab-macos "$key" '{secureData = <'"$hex"'>; string = "\U2318";}'
      done
    '';
  };
}
