# Mac part — left Cmd (Super_L) and left Opt (Alt_L) behave like macOS, so
# the same Mac-layout keyboard (in Mac mode — fn+O on Logitech) means the
# same thing on vega and polaris.
#
#   - GUI apps: Cmd → Ctrl; Cmd+arrows → line/document ends; Opt+arrows →
#     word/paragraph moves; Cmd/Opt+Backspace → delete line/word.
#   - ghostty: Cmd → Ctrl+Shift (its Linux defaults for copy/paste/tab/
#     window/search; Ctrl+C/W/T stay the shell's), plus the macOS ghostty
#     defaults Linux lacks. Opt stays Alt, like macos-option-as-alt on vega.
#
# Cmd stays a real Super key: unmapped chords reach niri, so Cmd+Q closes,
# Cmd+Space opens the launcher and holding Cmd+Tab keeps niri's switcher
# open like AltTab. Right Cmd is never remapped (rules name Super_L), so
# every niri Mod bind is still reachable.
{
  lib,
  yaml,
  hyperKey,
}:
let
  ghostty = "com.mitchellh.ghostty";

  letters = lib.stringToCharacters "abcdefghijklmnopqrstuvwxyz";
  digits = map toString (lib.range 0 9);
  symbols = [
    "minus"
    "equal"
    "leftbrace"
    "rightbrace"
    "semicolon"
    "apostrophe"
    "comma"
    "dot"
    "slash"
    "backslash"
  ];

  # { "Super_L-<key>" = "<mods>-<key>"; } for every key in keys.
  cmdAs = mods: keys: lib.listToAttrs (map (k: lib.nameValuePair "Super_L-${k}" "${mods}-${k}") keys);

  # Cmd+Q stays Super for niri (close window ≈ quit).
  cmdKeys = lib.subtractLists [ "q" ] letters ++ digits ++ symbols;

  gui = cmdAs "C" cmdKeys // {
    Super_L-left = "home";
    Super_L-right = "end";
    Super_L-up = "C-home";
    Super_L-down = "C-end";
    Super_L-backspace = [
      "Shift-home"
      "backspace"
    ];
    Super_L-Shift-leftbrace = "C-pageup"; # previous tab
    Super_L-Shift-rightbrace = "C-pagedown"; # next tab
    Alt_L-left = "C-left";
    Alt_L-right = "C-right";
    Alt_L-up = "C-up";
    Alt_L-down = "C-down";
    Alt_L-backspace = "C-backspace";
  };

  # Hammerspoon passes Cmd/Opt through hyper, so Hyper+Cmd+h is Cmd+Left.
  guiHyper = {
    "Super_L-${hyperKey}-h" = "home";
    "Super_L-${hyperKey}-l" = "end";
    "Super_L-${hyperKey}-k" = "C-home";
    "Super_L-${hyperKey}-j" = "C-end";
    "Alt_L-${hyperKey}-h" = "C-left";
    "Alt_L-${hyperKey}-l" = "C-right";
    "Alt_L-${hyperKey}-k" = "C-up";
    "Alt_L-${hyperKey}-j" = "C-down";
  };

  # Cmd+P stays Super for ghostty's super+p → nvim bind (modules/terminal/ghostty.nix).
  term =
    cmdAs "C-Shift" (lib.subtractLists [ "q" "p" ] letters)
    // {
      Super_L-Shift-f = "C-Alt-Shift-f"; # → nvim; Super+Shift+F is niri's
      Super_L-d = "C-Shift-o"; # new_split:right
      Super_L-Shift-d = "C-Shift-e"; # new_split:down
      Super_L-left = "home";
      Super_L-right = "end";
      Super_L-up = "C-Shift-pageup"; # jump_to_prompt:-1
      Super_L-down = "C-Shift-pagedown"; # jump_to_prompt:1
      Super_L-backspace = "C-u"; # kill line, as ghostty sends on macOS
      Super_L-leftbrace = "Super-C-leftbrace"; # goto_split:previous
      Super_L-rightbrace = "Super-C-rightbrace"; # goto_split:next
      Super_L-Shift-leftbrace = "C-pageup"; # previous_tab
      Super_L-Shift-rightbrace = "C-pagedown"; # next_tab
      Super_L-Alt_L-left = "C-Alt-left"; # goto_split:left
      Super_L-Alt_L-right = "C-Alt-right";
      Super_L-Alt_L-up = "C-Alt-up";
      Super_L-Alt_L-down = "C-Alt-down";
      Super_L-equal = "C-equal";
      Super_L-minus = "C-minus";
      Super_L-0 = "C-0";
    }
    // lib.listToAttrs (
      map (n: lib.nameValuePair "Super_L-${toString n}" "Alt-${toString n}") (lib.range 1 9)
    );

  termHyper = {
    "Super_L-${hyperKey}-h" = "home";
    "Super_L-${hyperKey}-l" = "end";
    "Super_L-${hyperKey}-k" = "C-Shift-pageup";
    "Super_L-${hyperKey}-j" = "C-Shift-pagedown";
  };
in
{
  home =
    { parentCfg, userCfg, ... }:
    let
      withHyper = rules: hyperRules: rules // lib.optionalAttrs parentCfg.hyper.enable hyperRules;
    in
    {
      xdg.configFile."xremap/mac.yml".source = yaml.generate "xremap-mac.yml" {
        keymap = [
          {
            name = "Mac: ghostty";
            application.only = [ ghostty ];
            remap = withHyper term termHyper;
          }
          {
            name = "Mac: GUI apps";
            application.not = [ ghostty ];
            remap = withHyper gui guiHyper;
          }
        ];
      };

      # macOS ghostty defaults with no Linux ctrl+shift equivalent.
      programs.ghostty.settings.keybind = lib.mkIf userCfg.ghostty.enable [
        "ctrl+alt+shift+f=text:\\x1b[70;6u" # Cmd+Shift+F, as vega's ghostty.nix
        "ctrl+shift+w=close_surface"
        "performable:ctrl+shift+k=clear_screen"
      ];
    };
}
