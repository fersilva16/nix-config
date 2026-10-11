# Noctalia Greeter (on greetd) — noctalia's own login screen (same widgets and
# visual language as the shell), pinned to the "Ink" look from
# modules/linux/noctalia: bone-on-black palette, square corners, the shell's
# monospace font on a flat black background.
#
# The palette is declared here instead of synced from the shell: Sync needs
# noctalia v5 + a polkit-elevated helper, and we're on v4 with frozen
# settings anyway. The scheme picker is hidden since the scheme is pinned.
#
# Sessions are discovered from XDG_DATA_DIRS / /run/current-system/sw/share
# (niri today); the greeter remembers the last one in its own sync.toml.
{ mkSystemModule, ... }:
let
  ink = import ./noctalia/ink.nix;
in
mkSystemModule {
  name = "noctalia-greeter";
  config.services.displayManager.noctalia-greeter = {
    enable = true;
    settings.appearance = {
      scheme = "Synced";
      scheme_selector_position = "hidden";
      theme_mode = "dark";
      corner_radius_scale = 0.0;
      # System-wide via modules/fonts/caskaydia-cove.nix, so the greeter
      # user's fontconfig sees it.
      font_family = "CaskaydiaCove Nerd Font";
      wallpaper.fill_color = ink.black;
      # Same mapping as noctalia's Ink scheme (dark).
      palette = {
        primary = ink.bone;
        on_primary = ink.black;
        secondary = ink.ash;
        on_secondary = ink.black;
        tertiary = ink.stone;
        on_tertiary = ink.black;
        error = ink.red;
        on_error = ink.bone;
        surface = ink.black;
        on_surface = ink.bone;
        surface_variant = ink.raised;
        on_surface_variant = ink.stone;
        outline = ink.ash;
        shadow = "#000000";
        hover = ink.bone;
        on_hover = ink.black;
      };
    };
  };
}
