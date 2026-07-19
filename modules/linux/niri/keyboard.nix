# niri keyboard part — us(intl) layout + macOS-style dead keys everywhere.
#
# Layers, bottom to top:
#   - xkb us(intl) in niri: ' " ` ~ ^ arm as dead keys.
#   - Composing is client-side. GTK apps (ghostty) compose via GTK's
#     builtin table + ~/.XCompose; libxkbcommon consumers find Compose
#     tables through XLOCALEDIR (NixOS has no /usr/share/X11/locale).
#   - Chrome's compose table is compiled into the binary and ignores
#     ~/.XCompose — fcitx5 over wayland text-input is the only way in;
#     fcitx5 composes with libxkbcommon, honoring the same ~/.XCompose.
#
# ~/.XCompose implements macOS/Windows us-intl semantics: only the fixed
# accent set composes; every other key emits mark+key immediately
# (' + s → 's — no ś, no dead-key space dance).
#
# Shared bindings come from the parent (modules/linux/niri/niri.nix),
# which embeds `kdl` into config.kdl when this part is enabled.
{ pkgs, lib }:
let
  usIntlCompose =
    let
      plain = lib.stringToCharacters "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
      namedPunct = {
        comma = ",";
        period = ".";
        semicolon = ";";
        colon = ":";
        exclam = "!";
        question = "?";
        parenright = ")";
        bracketright = "]";
        braceright = "}";
        minus = "-";
        slash = "/";
      };
      mkDead =
        dead: mark: composed:
        let
          entries =
            lib.listToAttrs (map (c: lib.nameValuePair c (mark + c)) plain)
            // lib.mapAttrs (_: c: mark + c) namedPunct
            // composed;
        in
        lib.concatStrings (lib.mapAttrsToList (k: v: "<${dead}> <${k}> : \"${v}\"\n") entries);
    in
    ''
      include "%L"

    ''
    + mkDead "dead_acute" "'" {
      a = "á";
      e = "é";
      i = "í";
      o = "ó";
      u = "ú";
      y = "ý";
      c = "ç";
      A = "Á";
      E = "É";
      I = "Í";
      O = "Ó";
      U = "Ú";
      Y = "Ý";
      C = "Ç";
    }
    + mkDead "dead_diaeresis" ''\"'' {
      a = "ä";
      e = "ë";
      i = "ï";
      o = "ö";
      u = "ü";
      y = "ÿ";
      A = "Ä";
      E = "Ë";
      I = "Ï";
      O = "Ö";
      U = "Ü";
      Y = "Ÿ";
    }
    + mkDead "dead_grave" "`" {
      a = "à";
      e = "è";
      i = "ì";
      o = "ò";
      u = "ù";
      A = "À";
      E = "È";
      I = "Ì";
      O = "Ò";
      U = "Ù";
    }
    + mkDead "dead_tilde" "~" {
      a = "ã";
      o = "õ";
      n = "ñ";
      A = "Ã";
      O = "Õ";
      N = "Ñ";
    }
    + mkDead "dead_circumflex" "^" {
      a = "â";
      e = "ê";
      i = "î";
      o = "ô";
      u = "û";
      A = "Â";
      E = "Ê";
      I = "Î";
      O = "Ô";
      U = "Û";
    };
in
{
  default = true;

  system = {
    # fcitx5 serves wayland text-input clients (Chrome) so the custom
    # ~/.XCompose table applies there too — Chrome's builtin compose table
    # is unreachable any other way. waylandFrontend: don't export
    # GTK_IM_MODULE/QT_IM_MODULE; GTK stays on "simple" (see kdl below).
    i18n.inputMethod = {
      enable = true;
      type = "fcitx5";
      fcitx5.waylandFrontend = true;
    };
  };

  # Embedded into config.kdl by the parent when this part is enabled.
  kdl = ''
    // US International with dead keys: ' " ` ~ ^ compose accents (' then e → é);
    // press space after to get the literal char. Swap variant to "altgr-intl"
    // for AltGr-only accents that leave those keys live.
    input {
        keyboard {
            xkb {
                layout "us"
                variant "intl"
            }
        }
    }

    // Dead keys arm in the compositor, but composing (dead_acute+e → é)
    // happens client-side via libxkbcommon, which finds Compose tables
    // through XLOCALEDIR. NixOS has no /usr/share/X11/locale, so without
    // this the sequences silently produce nothing.
    environment {
        XLOCALEDIR "${pkgs.libx11}/share/X11/locale"
        // Deliberately kept on "simple" even though fcitx5 runs: GTK4 +
        // fcitx5 over text-input crashes niri (niri-wm/niri#3850, open),
        // and ghostty is GTK4. GTK apps compose locally via the builtin
        // table + ~/.XCompose; fcitx5 only serves wayland-native
        // text-input clients (Chrome). Retire to fcitx once #3850 lands.
        GTK_IM_MODULE "simple"
        XMODIFIERS "@im=fcitx"
        // Make chrome/electron wrappers pick wayland-native ozone —
        // XWayland Chrome would bypass text-input-v3 and thus fcitx5.
        NIXOS_OZONE_WL "1"
    }

    spawn-at-startup "fcitx5"
  '';

  home = {
    home.file.".XCompose".text = usIntlCompose;

    # fcitx5 processes grabbed keys with its own layout, not the
    # compositor's — pin it to us(intl) or Chrome would get plain us.
    # fcitx5 tries to rewrite this on exit; the read-only HM symlink keeps
    # it declarative (GUI-side layout tweaks won't stick, intentionally).
    xdg.configFile."fcitx5/profile".text = ''
      [Groups/0]
      Name=Default
      Default Layout=us-intl
      DefaultIM=keyboard-us-intl

      [GroupOrder]
      0=Default
    '';
  };
}
