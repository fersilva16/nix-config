# Caps Lock hyper key — Linux port of modules/darwin/hammerspoon.
#
# keyd does at the evdev level what Hammerspoon does with eventtaps, minus
# all the Mach-port babysitting: hold Caps = hyper layer, tap Caps = Caps
# Lock. hjkl→arrows works in every app on both X11 and Wayland, and real
# modifiers (shift/alt/ctrl) pass through the layer, so hyper+shift+h
# selects left just like on macOS.
#
# App/window actions can't run commands from keyd, so the hyper layer emits
# Super+Ctrl+Alt chords that niri.nix binds (T/F/Tab/\).
{ mkUserModule, ... }:
mkUserModule {
  name = "keyd";
  system = {
    services.keyd = {
      enable = true;
      keyboards.default = {
        ids = [ "*" ];
        settings = {
          main = {
            capslock = "overload(hyper, capslock)";
            # Force hjkl usage — physical arrows are blocked, same as the
            # Hammerspoon arrowBlocker.
            left = "noop";
            right = "noop";
            up = "noop";
            down = "noop";
          };
          hyper = {
            h = "left";
            j = "down";
            k = "up";
            l = "right";
            ";" = "end"; # macOS Cmd+Right ≈ end of line
            # WM actions — chords caught by niri binds.
            t = "M-C-A-t"; # new terminal
            f = "M-C-A-f"; # maximize
            space = "M-C-A-space"; # toggle ghostty/vscode
            tab = "M-C-A-tab"; # focus next monitor
            "\\" = "M-C-A-\\"; # window to next monitor
          };
        };
      };
    };
  };
}
