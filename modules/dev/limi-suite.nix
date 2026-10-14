# Limi (inputs.limi): everything it ships, as one package (limi-suite). Limi
# ships no modules; the host-side wiring its tools need lives here.
#
# The suite lives in its own Nix profile, not in the Home Manager build, so a
# Limi change never touches nix-config:
#   limi switch            build ~/limi's working tree into the profile
#   limi switch --pinned   back to the version flake.lock pins
#   limi rollback          previous generation
#   limi status            which one is active
# A rebuild moves the profile to the pinned version only when it is missing or
# still on the pin the last rebuild set, so a fresh machine works, bumping the
# lock (`nix flake update limi`) takes effect, and a rebuild never undoes
# `limi switch`.
#
# Can't be enabled together with `omo` (asserted below): Limi's Nalum is omo,
# and both install `omo` and write the same ~/.omo files.
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

  # Next to Home Manager's own profile, so Nix treats it as a GC root too.
  profileRel = ".local/state/nix/profiles/limi";
  homeOf =
    username:
    forPlatform {
      darwin = "/Users/${username}";
      linux = "/home/${username}";
    };

  limi =
    profile:
    pkgs.writeShellApplication {
      name = "limi";
      text = ''
        profile=${profile}
        src="''${LIMI_SRC:-$HOME/limi}"
        # A running tmux sourced Nalum's tmux.conf at startup; re-source it so
        # the switched version applies without restarting the server.
        reload_tmux() {
          if command -v tmux >/dev/null && tmux has-session 2>/dev/null; then
            tmux source-file -q "$profile/share/nalum/tmux.conf"
          fi
        }
        case "''${1:-status}" in
          switch)
            if [ "''${2:-}" = --pinned ]; then
              nix-env --profile "$profile" --set ${pinned}
            else
              # Pure build of the working tree. Git flakes see tracked files
              # only: `git add -N` new ones first.
              nix build --no-link --profile "$profile" "git+file://$src#limi-suite"
            fi
            reload_tmux
            ;;
          rollback)
            nix-env --profile "$profile" --rollback
            reload_tmux
            ;;
          status)
            current="$(readlink -f "$profile")"
            if [ "$current" = ${pinned} ]; then
              echo "limi: pinned ($current)"
            else
              echo "limi: local build ($current)"
            fi
            ;;
          *)
            echo "usage: limi [switch [--pinned] | rollback | status]" >&2
            exit 2
            ;;
        esac
      '';
    };
in
mkUserModule {
  name = "limi-suite";
  requires = [ "omo-home" ];
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
      environment.profiles = lib.mkAfter [ "$HOME/${profileRel}" ];
    };
  };
  home =
    { username, userCfg, ... }:
    let
      profile = "${homeOf username}/${profileRel}";
      # Symlink to the pin the last rebuild set; outside the profiles dir so
      # nix never mistakes it for a profile.
      lastPin = "${homeOf username}/.local/state/limi/pinned";
    in
    lib.mkMerge [
      {
        assertions = [
          {
            assertion = !userCfg.omo.enable;
            message = "Enable limi-suite or omo, not both: both install `omo` and write ~/.omo.";
          }
        ];
        home = {
          packages = [ (limi profile) ];
          sessionPath = [ "${profile}/bin" ];
          activation.limiProfile = {
            after = [ "writeBoundary" ];
            before = [ ];
            data = ''
              # Missing, or still on the last pin: follow the lock. Anything
              # else is a `limi switch` build, which a rebuild leaves alone.
              if [ ! -e ${profile} ] || [ "$(readlink -f ${profile})" = "$(readlink ${lastPin} 2>/dev/null)" ]; then
                if [ "$(readlink -f ${profile} 2>/dev/null)" != ${pinned} ]; then
                  run mkdir -p "$(dirname ${profile})"
                  run ${pkgs.nix}/bin/nix-env --profile ${profile} --set ${pinned}
                fi
              fi
              run mkdir -p "$(dirname ${lastPin})"
              run ln -sfn ${pinned} ${lastPin}
            '';
          };
        };
      }
      # Nalum's tmux wiring: csi-u, prefix+N and the notifier hooks, the
      # notifier's status-bar widget, and the window icon for omo panes. Read
      # through the profile, so `limi switch` updates them too.
      (lib.mkIf userCfg.tmux.enable {
        programs.tmux.extraConfig = "source-file -q ${profile}/share/nalum/tmux.conf";
        xdg.configFile = {
          # Appends to the `icons:` map cli/tmux/theme.nix writes, so it must
          # land after it. Glyph is U+F51B, chosen by hand: keep it.
          "tmux/tmux-nerd-font-window-name.yml".text = lib.mkAfter "  omo: \"\"";
          "tmux/widgets/10-notify" = {
            executable = true;
            text = ''
              #!/usr/bin/env bash
              exec ${profile}/bin/tmux-agent-notify widget
            '';
          };
        };
      })
    ];
}
