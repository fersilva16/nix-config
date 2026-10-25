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
# shadow the host's own omo. Nalum keeps its own home (`host.nalumHome`) and
# leaves ~/.omo to the host's omo. It still reads ~/.omo's omo.jsonc and rules,
# and omo unpacks Nalum's version into ~/.omo/binary-runtime: omo has no
# variable for either.
{
  mkUserModule,
  forPlatform,
  inputs,
  pkgs,
  lib,
  fleetPeers,
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
  extraOptions.peers = lib.mkOption {
    type = lib.types.attrsOf (lib.types.listOf lib.types.str);
    default = { };
    example = {
      polaris = [
        "-D"
        "1080"
      ];
    };
    description = ''
      Extra ssh arguments per machine limi-desktop, its session picker and
      `limi attach` can reach. Fleet peers that advertise "ssh"
      (modules/system/fleet.nix) are always listed; an entry here adds args
      or a machine outside the fleet. Nothing connects until you pick one.
    '';
  };
  parts = {
    server = import ./server.nix {
      inherit
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
    {
      cfg,
      username,
      userCfg,
      ...
    }:
    # Nested function for home-manager's `config` (mkOutOfStoreSymlink),
    # which mkUserModule's home builder doesn't pass.
    { config, ... }:
    let
      profile = "${homeOf username}/${host.profile}";
      limiPath = "${profile}/${host.path}";
      # The picker's hop targets: every fleet peer that advertises "ssh",
      # plus `peers`, each with its ssh args.
      machines =
        lib.mapAttrs (_: _: [ ]) (lib.filterAttrs (_: peer: lib.elem "ssh" peer.services) fleetPeers)
        // cfg.peers;
      # launchd starts jobs with PATH=/usr/bin:/bin:/usr/sbin:/sbin. The
      # suite's scripts call `tmux` from PATH, which must be limi-path's shim
      # so they reach limi-desktop's mux; `td` comes from Homebrew.
      jobPath = lib.concatStringsSep ":" [
        limiPath
        "${profile}/bin"
        "/etc/profiles/per-user/${username}/bin"
        "/run/current-system/sw/bin"
        "/opt/homebrew/bin"
        "/usr/bin"
        "/bin"
        "/usr/sbin"
        "/sbin"
      ];
      # The tmux options the suite's scripts read and only the host knows.
      # Each mirrors the option the matching nix-config module already has.
      hostOptions =
        lib.optionals (userCfg.slack.enable && userCfg.slack.later.enable) [
          "set -g @slack-later-workspace ${lib.escapeShellArg userCfg.slack.later.workspace}"
          "set -g @slack-later-group ${userCfg.slack.later.groupBy}"
        ]
        ++ lib.optional userCfg.todoist.enable "set -g @todoist-warn-at ${toString userCfg.todoist.warnAt}";
      inherit (userCfg.todoist) reviewAt;
      reviewHM = lib.splitString ":" (if reviewAt != null then reviewAt else "0:0");
    in
    lib.mkMerge [
      # The machines limi-desktop, its session picker and `limi attach` reach
      # over ssh, one per line, `name [ssh args]`. The file replaces the
      # suite's own list, so an empty one is never written.
      (lib.mkIf (machines != { }) {
        xdg.configFile."limi/machines".text = lib.concatStrings (
          lib.mapAttrsToList (name: args: lib.concatStringsSep " " ([ name ] ++ args) + "\n") machines
        );
      })
      # The mux sources this file after every tmux.d, so these win over the
      # suite's defaults; `limi switch` never touches it. A running mux reads
      # it again on prefix+R. On Linux the host tmux reads it too, through
      # mux.conf.
      (lib.mkIf (hostOptions != [ ]) {
        home.file.${host.hostConf}.text = lib.concatMapStrings (line: line + "\n") hostOptions;
      })
      # With no `omo` of its own, Nalum is this host's omo, so its home is
      # ~/.omo: the same config, sessions and login, and whatever omo-home
      # modules drop there. It must exist before that Nalum first runs, or
      # Nalum makes a real directory here and this link collides.
      #
      # Nalum's launch links its own rules/tmux.md and rules/worktree-stacks.md
      # (its `omoHome`) into that same directory, so Home Manager must not
      # manage them too, or the next rebuild fails with "would be clobbered".
      # Nalum's copies cover the same ground (tmux.md adds the limi-mux shim).
      (lib.mkIf (!userCfg.omo.enable) {
        home.file = {
          ${host.nalumHome}.source = config.lib.file.mkOutOfStoreSymlink "${homeOf username}/.omo";
          ".omo/rules/tmux.md".enable = lib.mkIf userCfg.tmux.enable false;
          ".omo/rules/worktree-stacks.md".enable = lib.mkIf (
            userCfg.worktree.enable && userCfg.worktree.stack.enable
          ) false;
        };
      })
      # limi-desktop draws with Ghostty's config (~/.config/ghostty/config
      # first). With the Ghostty app off nothing writes that file, so write
      # the same look here: programs.ghostty with no package is only the file.
      # Same settings as terminal/ghostty.nix; with the app on, that module
      # writes it.
      (lib.mkIf (!userCfg.ghostty.enable) {
        programs.ghostty = {
          enable = true;
          package = null;
          settings = {
            theme = "Flexoki Light";

            font-family = "CaskaydiaCove Nerd Font";
            font-family-bold = "CaskaydiaCove Nerd Font";
            font-family-italic = "auto";
            font-family-bold-italic = "auto";
            font-size = 12;

            cursor-style = "bar";
            cursor-style-blink = true;
            adjust-cursor-thickness = 2;

            macos-option-as-alt = true;
            macos-titlebar-style = "transparent";
            window-theme = "auto";
            gtk-titlebar = false;

            window-padding-x = 8;
            window-padding-y = 8;

            # Cmd+P and Cmd+Shift+F reach Neovim as CSI-u sequences.
            keybind = [
              "super+p=text:\\x1b[80;6u"
              "super+shift+f=text:\\x1b[70;6u"
            ];
          };
        };
      })
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
      # omo panes. Linux only: there the host's tmux is the suite's mux. On
      # macOS limi-desktop runs its own mux and ships both empty, so the host
      # tmux stays as it was.
      (forPlatform {
        linux = lib.mkIf userCfg.tmux.enable {
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
          # The suite's timers, run from limi-path against limi-desktop's mux.
          # Labels differ from nix-config's own wt-pool-refresh and
          # tmux-todoist-review agents, which serve the host tmux while those
          # modules are on. Two pool refreshes are safe (wt-pool-fill takes a
          # lock); the review is the mux's only once host tmux is off, so one
          # popup gates the day.
          {
            # Every 15 minutes, low priority. A run with nothing to rebuild is
            # a fetch and a `git status` per pool.
            launchd.agents.limi-wt-pool-refresh = {
              enable = true;
              config = {
                ProgramArguments = [ "${limiPath}/wt-pool-refresh" ];
                EnvironmentVariables.PATH = jobPath;
                RunAtLoad = false;
                StartInterval = 900;
                ProcessType = "Background";
                LowPriorityIO = true;
                Nice = 10;
              };
            };
            # Local wall-clock: 06:00 stays 06:00 after a flight, and a missed
            # run fires on wake. Never at load, so a 3pm login does not fire
            # the morning review.
            launchd.agents.limi-todoist-review =
              lib.mkIf (userCfg.todoist.enable && reviewAt != null && !userCfg.tmux.enable)
                {
                  enable = true;
                  config = {
                    ProgramArguments = [ "${limiPath}/tmux-todoist-review" ];
                    EnvironmentVariables.PATH = jobPath;
                    StartCalendarInterval = [
                      {
                        Hour = lib.toIntBase10 (builtins.elemAt reviewHM 0);
                        Minute = lib.toIntBase10 (builtins.elemAt reviewHM 1);
                      }
                    ];
                    RunAtLoad = false;
                    ProcessType = "Interactive";
                  };
                };
          }
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
            # After every other init. shellInit runs in every fish, so a
            # plain `fish -c` gets it too; interactive runs again after
            # fish.nix's PATH juggling, which lives there.
            programs.fish =
              let
                first = ''
                  if contains -- ${limiPath} $PATH
                    set -gx PATH ${limiPath} (string match -v -- ${limiPath} $PATH)
                  end
                '';
              in
              {
                shellInit = lib.mkAfter first;
                interactiveShellInit = lib.mkAfter first;
              };
          })
        ];
      })
    ];
}
