# Limi (inputs.limi): everything it ships, as one package (limi-suite). Limi
# owns its tools, its `limi` CLI and the paths a host wires (`lib.host`); this
# module is only the host glue.
#
# The suite lives in its own Nix profile, not in the Home Manager build, so a
# Limi change never touches nix-config: `limi switch` builds ~/limi into it,
# `limi switch --pinned` goes back to the version flake.lock pins. Each
# activation hands that pin to `limi pin`, which follows it unless a
# `limi switch` build is active.
#
# Works next to `omo`: the suite's `omo` and `nalum` live in limi-path
# (`host.path`), which only limi-desktop and its mux put on PATH, so they never
# reach the host's own omo or ~/.omo.
{
  mkUserModule,
  forPlatform,
  inputs,
  pkgs,
  lib,
  ...
}:
let
  pinned = inputs.limi.packages.${pkgs.stdenv.hostPlatform.system}.limi-suite;
  inherit (inputs.limi.lib) host;
  homeOf =
    username:
    forPlatform {
      darwin = "/Users/${username}";
      linux = "/home/${username}";
    };
in
mkUserModule {
  name = "limi-suite";
  requires = [ "omo-home" ];
  parts = {
    gateway = import ./gateway.nix {
      inherit
        pkgs
        host
        homeOf
        forPlatform
        ;
    };
  };
  # Nalum's linux binary is generic glibc (/lib64/ld-linux-x86-64.so.2), and so
  # are the native modules and senpi-desktop-engine it unpacks into
  # ~/.omo/binary-runtime at run time, where patchelf can't reach them.
  # nix-ld serves that loader path, so all of them run unpatched.
  #
  # The profile also joins NixOS's profile list, so the whole graphical
  # session (Noctalia's launcher included) gets its share/ on XDG_DATA_DIRS
  # (desktop entries such as limi-desktop) and its bin/ on PATH. A new
  # entry shows up after the next login.
  system = forPlatform {
    linux = {
      programs.nix-ld.enable = true;
      # Last, so it never shadows /run/wrappers or the system profiles.
      environment.profiles = lib.mkAfter [ "$HOME/${host.profile}" ];
    };
  };
  home =
    { username, userCfg, ... }:
    let
      profile = "${homeOf username}/${host.profile}";
      limiPath = "${profile}/${host.path}";
    in
    lib.mkMerge [
      {
        home = {
          sessionPath = [ "${profile}/bin" ];
          # `limi pin` runs nix-env from PATH; hand it this host's nix.
          activation.limiProfile = {
            after = [ "writeBoundary" ];
            before = [ ];
            data = ''
              run env PATH="${pkgs.nix}/bin:$PATH" ${pinned}/bin/limi pin ${pinned}
            '';
          };
        };
      }
      # The suite's tmux config and status-bar widget, read through the
      # profile so `limi switch` updates them too, plus the window icon for
      # omo panes.
      (lib.mkIf userCfg.tmux.enable {
        programs.tmux.extraConfig = "source-file -q ${profile}/${host.tmuxConf}";
        xdg.configFile = {
          # Appends to the `icons:` map cli/tmux/theme.nix writes, so it must
          # land after it. Glyph is U+F51B, chosen by hand: keep it. `omo`
          # adds the same entry, and a second `omo:` key breaks the map.
          "tmux/tmux-nerd-font-window-name.yml" = lib.mkIf (!userCfg.omo.enable) {
            text = lib.mkAfter "  omo: \"\"";
          };
          "tmux/widgets/10-limi" = {
            executable = true;
            text = ''
              #!/usr/bin/env bash
              exec ${profile}/${host.tmuxWidget} "$@"
            '';
          };
        };
      })
      # limi-desktop and its mux start each pane with limi-path first, so a
      # bare `tmux` there is the suite's shim. On macOS a login shell then
      # reorders PATH (path_helper, fish's PATH juggling, ~/.profile), so move
      # it back to the front. Only processes under limi-desktop have limi-path
      # on PATH at all, so every other shell is left as it is. On Linux the
      # shim is the host's `tmux` anyway.
      (forPlatform {
        darwin = lib.mkMerge [
          {
            # agents/* panes run `/bin/sh -l`, which reads ~/.profile. That
            # file isn't ours (installers append to it), so only make sure it
            # sources ours, last; the guard keeps it harmless once the module
            # is off.
            xdg.configFile."limi/profile.sh".text = ''
              # shellcheck shell=sh
              limi_path="${limiPath}"
              case ":$PATH:" in
                *":$limi_path:"*)
                  limi_rest=
                  limi_ifs=$IFS
                  IFS=:
                  for limi_dir in $PATH; do
                    [ "$limi_dir" = "$limi_path" ] || limi_rest="$limi_rest:$limi_dir"
                  done
                  IFS=$limi_ifs
                  PATH="$limi_path$limi_rest"
                  ;;
              esac
              unset limi_path limi_rest limi_ifs limi_dir
            '';
            home.activation.limiPathProfile = {
              after = [ "writeBoundary" ];
              before = [ ];
              data = ''
                f="$HOME/.profile"
                line='[ -r "$HOME/.config/limi/profile.sh" ] && . "$HOME/.config/limi/profile.sh"'
                grep -qxF "$line" "$f" 2>/dev/null || printf '%s\n' "$line" >> "$f"
              '';
            };
          }
          (lib.mkIf userCfg.fish.enable {
            # After every other init (fish's PATH juggling included). Login
            # covers `fish -lc`; interactive covers a plain `fish` in a pane.
            programs.fish =
              let
                first = ''
                  if contains -- ${limiPath} $PATH
                    set -gx PATH ${limiPath} (string match -v -- ${limiPath} $PATH)
                  end
                '';
              in
              {
                loginShellInit = lib.mkAfter first;
                interactiveShellInit = lib.mkAfter first;
              };
          })
        ];
      })
    ];
}
