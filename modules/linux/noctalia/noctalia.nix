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
  config,
  pkgs,
  lib,
  ...
}:
let
  baseSettings = lib.importJSON ./settings.json;

  # v4's SystemMonitor can't show GPU usage/VRAM and can't be extended, so on
  # NVIDIA hosts it's swapped for ./sysmon: a local plugin with the same
  # CPU/temp/RAM gauges plus GPU + VRAM, and a merged history panel on click.
  # Installed read-only into ~/.config/noctalia/plugins.
  hasNvidia = config.modules.system.nvidia.enable or false;
  sysmonFiles = {
    "manifest.json" = ./sysmon/manifest.json;
    "BarWidget.qml" = ./sysmon/BarWidget.qml;
    "Metric.qml" = ./sysmon/Metric.qml;
    "Panel.qml" = ./sysmon/Panel.qml;
    "Main.qml" = pkgs.replaceVars ./sysmon/Main.qml {
      nvidiaSmi = "${lib.getBin config.hardware.nvidia.package}/bin/nvidia-smi";
    };
  };
  leftWidgets = map (
    w: if hasNvidia && w.id == "SystemMonitor" then { id = "plugin:sysmon"; } else w
  ) baseSettings.bar.widgets.left;

  # Single source for the palette: noctalia scheme.
  ink = import ./ink.nix;

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

  # Ink for GTK apps: libadwaita's named colors, which adw-gtk3 (GTK 3)
  # reads too. Written by hand rather than via noctalia's gtk template,
  # which would rewrite gtk.css at runtime.
  gtkCss = ''
    @define-color accent_color ${ink.bone};
    @define-color accent_bg_color ${ink.bone};
    @define-color accent_fg_color ${ink.black};
    @define-color destructive_bg_color ${ink.red};
    @define-color destructive_fg_color ${ink.bone};
    @define-color error_color ${ink.red};
    @define-color window_bg_color ${ink.black};
    @define-color window_fg_color ${ink.bone};
    @define-color view_bg_color ${ink.black};
    @define-color view_fg_color ${ink.bone};
    @define-color headerbar_bg_color ${ink.raised};
    @define-color headerbar_fg_color ${ink.bone};
    @define-color sidebar_bg_color ${ink.raised};
    @define-color sidebar_fg_color ${ink.bone};
    @define-color card_bg_color ${ink.raised};
    @define-color card_fg_color ${ink.bone};
    @define-color popover_bg_color ${ink.raised};
    @define-color popover_fg_color ${ink.bone};
    @define-color dialog_bg_color ${ink.raised};
    @define-color dialog_fg_color ${ink.bone};
  '';
in
mkUserModule {
  name = "noctalia";
  # All shell glue lives in niri's config.kdl — useless without niri here.
  requires = [ "niri" ];
  parts.screen-recorder = import ./screen-recorder.nix { inherit pkgs; };
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
  home =
    { userCfg, ... }:
    {
      imports = [ inputs.noctalia.homeModules.default ];

      gtk = lib.mkIf userCfg.gtk.enable {
        gtk3.extraCss = gtkCss;
        gtk4.extraCss = gtkCss;
      };

      programs.noctalia-shell = {
        enable = true;
        package = inputs.noctalia.packages.${system}.default;
        settings = lib.recursiveUpdate baseSettings {
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
            widgets.left = leftWidgets;
          };
          ui = {
            boxBorderEnabled = true;
            fontDefault = font;
            fontFixed = font;
            panelBackgroundOpacity = 1;
          };
        };
        # Enables the local plugins. Default source listed so noctalia doesn't
        # try to write it back into the read-only plugins.json on load.
        plugins = {
          version = 2;
          sources = [
            {
              name = "Noctalia Plugins";
              url = "https://github.com/noctalia-dev/noctalia-plugins";
              enabled = true;
            }
          ];
          states = {
            polkit-agent = {
              enabled = true;
              sourceUrl = "local";
            };
            sysmon = lib.mkIf hasNvidia {
              enabled = true;
              sourceUrl = "local";
            };
          };
        };
      };

      xdg.configFile = {
        # noctalia writes a default plugins.json on first start; replace it.
        "noctalia/plugins.json".force = true;
        # The polkit agent (1Password unlock, pkexec, YubiKey touch), drawn
        # in noctalia's Ink style. Vendored from noctalia-dev/noctalia-plugins
        # polkit-agent 1.0.6 (ea21cb6) so it can be restyled here.
        "noctalia/plugins/polkit-agent".source = ./polkit-agent;
        "noctalia/plugins/sysmon" = lib.mkIf hasNvidia {
          source = pkgs.linkFarm "noctalia-sysmon" sysmonFiles;
        };

        # Noctalia scans colorschemes/<Name>/<Name>.json (find -L, so a store
        # symlink is fine). Always dark; light mirrors it as ink-on-paper.
        "noctalia/colorschemes/Ink/Ink.json".text = builtins.toJSON {
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
    };
}
