{ mkSystemModule, ... }:
mkSystemModule {
  name = "darwin-default";
  config = {
    system.defaults = {
      trackpad = {
        Clicking = true;
        TrackpadThreeFingerDrag = true;
      };

      dock = {
        # Disable hot corner quick note
        wvous-br-corner = 1;

        # Disable rearrange of desktops
        mru-spaces = false;

        autohide = true;
        show-recents = false;
      };

      finder = {
        AppleShowAllExtensions = true;
        AppleShowAllFiles = true;

        # Trash is stuff already decided against — don't let it accumulate.
        FXRemoveOldTrashItems = true;
      };

      menuExtraClock = {
        ShowAMPM = true;
      };
    };
  };
}
