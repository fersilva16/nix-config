{ mkUserModule, ... }:
# AltTab — window switcher. Single source of truth: ./config.plist, exported
# straight from AltTab. The activation script merges it into AltTab's prefs with
# `defaults import` (cfprefsd-safe; merges, so AltTab's own telemetry/state keys
# survive). The two ⌘ shortcuts ride along as native <data> in the plist.
# To update: re-export from AltTab over config.plist, then rebuild + restart AltTab.
mkUserModule {
  name = "alt-tab";
  system.homebrew.casks = [ "alt-tab" ];
  home.home.activation.altTabConfig = {
    after = [ "writeBoundary" ];
    before = [ ];
    data = ''
      /usr/bin/defaults import com.lwouis.alt-tab-macos ${./config.plist}
    '';
  };
}
