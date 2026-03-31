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
  };
  home = {
    home.file.".hammerspoon/init.lua" = {
      source = ./init.lua;
    };
  };
}
