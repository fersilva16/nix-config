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
# Limi owns the agent (Nalum is the host's omo, add-ons included), tmux
# (limi-desktop's mux), the wt/wts family, `lin` and the Todoist and Slack
# Later tools; nix-config has no copies of them. The suite's `omo` and the tmux tools live in limi-path (`host.path`),
# which limi-desktop and its mux put first on PATH.
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
  extraOptions.slackLater = {
    workspace = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "example.slack.com";
      description = ''
        Exact Slack workspace domain for the suite's Slack Later count and
        popup (`@slack-later-workspace`). Empty keeps Slack Later off.
      '';
    };
    groupBy = lib.mkOption {
      type = lib.types.enum [
        "channel"
        "flat"
      ];
      default = "channel";
      description = "The view the Slack Later popup opens in (`@slack-later-group`).";
    };
  };
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
      hostOptions =
        lib.optionals (cfg.slackLater.workspace != "") [
          "set -g @slack-later-workspace ${lib.escapeShellArg cfg.slackLater.workspace}"
          "set -g @slack-later-group ${cfg.slackLater.groupBy}"
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
      # Nalum is this host's omo, so its home is ~/.omo: the same config,
      # sessions and login, and whatever omo-home modules drop there. It must
      # exist before that Nalum first runs, or Nalum makes a real directory
      # here and this link collides.
      {
        home.file.${host.nalumHome}.source = config.lib.file.mkOutOfStoreSymlink "${homeOf username}/.omo";
      }
      # The nvim half of the mux's Alt+hjkl pane navigation. Normal mode only,
      # so visual-mode Alt+j/k (move selection) still reaches nvim's map.
      (lib.mkIf userCfg.nvim.enable {
        programs.neovim.plugins = [
          {
            plugin = pkgs.vimPlugins.vim-tmux-navigator;
            config = ''
              vim.g.tmux_navigator_no_mappings = 1
              vim.keymap.set('n', '<A-h>', '<cmd>TmuxNavigateLeft<cr>', { desc = 'Window/pane left', silent = true })
              vim.keymap.set('n', '<A-j>', '<cmd>TmuxNavigateDown<cr>', { desc = 'Window/pane down', silent = true })
              vim.keymap.set('n', '<A-k>', '<cmd>TmuxNavigateUp<cr>', { desc = 'Window/pane up', silent = true })
              vim.keymap.set('n', '<A-l>', '<cmd>TmuxNavigateRight<cr>', { desc = 'Window/pane right', silent = true })
            '';
          }
        ];
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
          # Login shells in agents/* tmux sessions get Nalum's agent PATH
          # (its gh shim first). ~/.profile isn't ours (installers append to
          # it), so only make sure it sources Nalum's file; the guard keeps it
          # harmless once the suite is gone.
          activation.limiAgentProfile = {
            after = [ "writeBoundary" ];
            before = [ ];
            data = ''
              f="$HOME/.profile"
              line='[ -r "$HOME/${host.profile}/${host.agentProfile}" ] && . "$HOME/${host.profile}/${host.agentProfile}"'
              grep -qxF "$line" "$f" 2>/dev/null || printf '%s\n' "$line" >> "$f"
            '';
          };
        };
      }
      # limi-desktop and its mux start each pane with limi-path first, so a
      # bare `tmux` there is the suite's shim. On macOS a login shell then
      # reorders PATH (path_helper, fish's PATH juggling, ~/.profile), so move
      # it back to the front. Only processes under limi-desktop have limi-path
      # on PATH at all, so every other shell is left as it is. On Linux the
      # shim is the host's `tmux` anyway.
      (forPlatform {
        darwin = lib.mkMerge [
          # The suite's timers, run from limi-path against limi-desktop's mux.
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
            launchd.agents.limi-todoist-review = lib.mkIf (userCfg.todoist.enable && reviewAt != null) {
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
