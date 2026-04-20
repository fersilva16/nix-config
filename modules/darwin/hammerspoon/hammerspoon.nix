{ mkUserModule, ... }:
mkUserModule {
  name = "hammerspoon";
  system = {
    homebrew.casks = [ "hammerspoon" ];

    # Remap Caps Lock → F18 at the kernel level via hidutil (zero latency).
    # Hammerspoon then interprets F18 as Hyper / tap-for-Caps Lock.
    system.keyboard = {
      enableKeyMapping = true;
      userKeyMapping = [
        {
          # Caps Lock (0x39) → F18 (0x6D)
          HIDKeyboardModifierMappingSrc = 30064771129; # 0x700000039
          HIDKeyboardModifierMappingDst = 30064771181; # 0x70000006D
        }
      ];
    };

    # Disable App Nap for Hammerspoon.
    #
    # Hammerspoon is a background agent with no visible windows, so macOS App
    # Nap is free to throttle its run loop and timers when the user isn't
    # actively interacting with it. When throttled:
    #   - hs.timer callbacks fire sparsely or not at all
    #   - The proactive 30s eventtap recreate in init.lua stops running
    #   - Secure Input / stuck-hyper recovery stops running
    #   - Any transient tap hiccup becomes a permanent outage until the user
    #     types enough to wake the app, at which point it "magically" recovers
    #
    # Opting out of App Nap keeps the run loop at normal priority and lets the
    # health checks in init.lua actually do their job.
    system.defaults.CustomUserPreferences = {
      "org.hammerspoon.Hammerspoon" = {
        NSAppSleepDisabled = true;
      };
    };
  };
  home = {
    home.file.".hammerspoon/init.lua" = {
      source = ./init.lua;
    };
  };
}
