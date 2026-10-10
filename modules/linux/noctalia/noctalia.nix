# Noctalia — desktop shell for niri (bar, launcher, notifications, lock
# screen, control center, wallpaper, OSDs). Replaces the previous
# waybar/fuzzel/swaync/swaylock stack in one cohesive layer.
#
# Pinned to the stable v4 line (quickshell-based); see the flake input.
#
# Look: "Ink" — monochrome woodcut/engraving to match the scratchboard
# wallpaper, and to strip noctalia's Material-You (Android) feel: square
# corners, hairline outlines instead of soft shadows, no pill capsules,
# flat compact bar, monospace UI font, bone-on-black palette with a single
# printer's-red for errors.
#
# Settings are frozen: ./settings.json is the GUI-exported baseline (Settings
# -> General -> Copy Settings), and `ink` below overrides the look on top of
# it. ~/.config/noctalia/settings.json becomes a read-only symlink, so GUI
# tweaks no longer persist — re-export into ./settings.json to keep one.
#
# The niri-side glue (spawn-at-startup, IPC keybinds, layer rules, window
# borders/shadow) lives in modules/linux/niri/niri.nix, which owns config.kdl.
{
  mkUserModule,
  inputs,
  system,
  lib,
  ...
}:
let
  # Single source for the palette: noctalia scheme.
  ink = {
    black = "#0a0a0a";
    raised = "#161616";
    bone = "#e8e2d4";
    ash = "#bdb6a6";
    stone = "#8f8a80";
    slate = "#3a3833";
    red = "#b23a2e";
  };

  terminal = {
    normal = {
      black = ink.slate;
      inherit (ink) red;
      green = "#8a9a6b";
      yellow = "#c9b27c";
      blue = "#7d8a99";
      magenta = "#9a7d8f";
      cyan = "#7f9994";
      white = ink.ash;
    };
    bright = {
      black = ink.stone;
      red = "#c8524a";
      green = "#a3b386";
      yellow = "#dcc89a";
      blue = "#98a5b3";
      magenta = "#b398a9";
      cyan = "#9ab3ae";
      white = ink.bone;
    };
    foreground = ink.bone;
    background = ink.black;
    selectionFg = ink.black;
    selectionBg = ink.bone;
    cursorText = ink.black;
    cursor = ink.bone;
  };

  # Hover inverts (bone fill, ink text) like a print negative.
  scheme = {
    mPrimary = ink.bone;
    mOnPrimary = ink.black;
    mSecondary = ink.ash;
    mOnSecondary = ink.black;
    mTertiary = ink.stone;
    mOnTertiary = ink.black;
    mError = ink.red;
    mOnError = ink.bone;
    mSurface = ink.black;
    mOnSurface = ink.bone;
    mSurfaceVariant = ink.raised;
    mOnSurfaceVariant = ink.stone;
    mOutline = ink.ash;
    mShadow = "#000000";
    mHover = ink.bone;
    mOnHover = ink.black;
    inherit terminal;
  };

  font = "CaskaydiaCove Nerd Font";
in
mkUserModule {
  name = "noctalia";
  # All shell glue lives in niri's config.kdl — useless without niri here.
  requires = [ "niri" ];
  system = {
    # Pre-built binaries for noctalia + its quickshell fork.
    nix.settings = {
      extra-substituters = [ "https://noctalia.cachix.org" ];
      extra-trusted-public-keys = [
        "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
      ];
    };
    # Power widgets need these; NetworkManager + bluetooth are already
    # host-wide modules.
    services.upower.enable = true;
    services.power-profiles-daemon.enable = true;
  };
  home = {
    imports = [ inputs.noctalia.homeModules.default ];

    programs.noctalia-shell = {
      enable = true;
      package = inputs.noctalia.packages.${system}.default;
      settings = lib.recursiveUpdate (lib.importJSON ./settings.json) {
        colorSchemes = {
          predefinedScheme = "Ink";
          useWallpaperColors = false;
          darkMode = true;
        };
        general = {
          radiusRatio = 0;
          boxRadiusRatio = 0;
          iRadiusRatio = 0;
          screenRadiusRatio = 0;
          enableShadows = false;
        };
        bar = {
          density = "compact";
          showCapsule = false;
          outerCorners = false;
          showOutline = true;
          backgroundOpacity = 1;
          frameRadius = 0;
        };
        ui = {
          boxBorderEnabled = true;
          fontDefault = font;
          fontFixed = font;
          panelBackgroundOpacity = 1;
        };
      };
    };

    # Noctalia scans colorschemes/<Name>/<Name>.json (find -L, so a store
    # symlink is fine). Always dark; light mirrors it as ink-on-paper.
    xdg.configFile."noctalia/colorschemes/Ink/Ink.json".text = builtins.toJSON {
      dark = scheme;
      light = scheme // {
        mPrimary = ink.black;
        mOnPrimary = ink.bone;
        mSurface = ink.bone;
        mOnSurface = ink.black;
        mSurfaceVariant = ink.ash;
        mOnSurfaceVariant = ink.slate;
        mOutline = ink.slate;
        mHover = ink.black;
        mOnHover = ink.bone;
      };
    };
  };
}
