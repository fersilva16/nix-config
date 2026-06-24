{ mkUserModule, ... }:
# macOS has a single global "natural scrolling" switch for trackpad *and* mouse.
# Keep macOS natural scrolling ON (trackpad stays natural) and let Scroll Reverser
# invert *only the mouse* back to normal. Prefs domain/keys from upstream source.
mkUserModule {
  name = "scroll-reverser";
  system = {
    homebrew.casks = [ "scroll-reverser" ];
    system.defaults.CustomUserPreferences."com.pilotmoon.scroll-reverser" = {
      InvertScrollingOn = true; # master enable
      ReverseY = true; # vertical
      ReverseX = false;
      ReverseMouse = true; # mouse → normal
      ReverseTrackpad = false; # trackpad → leave natural
    };
  };
}
