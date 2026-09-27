# Slack "Later" as an ambient count in the tmux bar.
#
# There is no supported Later API. The widget is therefore deliberately opt-in
# and uses only the dedicated Chrome profile at
# ~/.local/share/tmux-slack-later/chrome/Default. It never reads desktop Slack
# or a regular Chrome profile, and a failed extraction is not evidence that
# Chrome or Slack signed out.
{ pkgs, lib }:
{
  default = false;

  # lib comes from the module args, NOT pkgs.lib: an option DECLARATION that
  # forces pkgs is circular here (pkgs needs nixpkgs.overlays, which needs the
  # declarations complete), and nix reports it only as "infinite recursion".
  extraOptions.workspace = lib.mkOption {
    type = lib.types.str;
    default = "";
    example = "telepatiaworkspace.slack.com";
    description = ''
      Exact Slack workspace domain the Later count belongs to. It is checked
      against auth.test's URL host before any saved.list result is published.
      An empty or non-matching domain fails closed.
    '';
  };

  home =
    {
      cfg,
      lib,
      userCfg,
      ...
    }:
    let
      runtimeInputs = with pkgs; [
        coreutils
        curl
        findutils
        gnugrep
        jq
        openssl
        sqlite
      ];

      tmux-slack-later-refresh = pkgs.writeShellApplication {
        name = "tmux-slack-later-refresh";
        inherit runtimeInputs;
        text = ''
          export TMUX_SLACK_LATER_PROFILE="$HOME/.local/share/tmux-slack-later/chrome/Default"
          export TMUX_SLACK_LATER_WORKSPACE=${lib.escapeShellArg cfg.workspace}
          exec ${pkgs.bash}/bin/bash ${./later.sh} refresh "$@"
        '';
      };

      tmux-slack-later-widget = pkgs.writeShellApplication {
        name = "tmux-slack-later-widget";
        runtimeInputs = runtimeInputs ++ [ tmux-slack-later-refresh ];
        text = ''
          export TMUX_SLACK_LATER_PROFILE="$HOME/.local/share/tmux-slack-later/chrome/Default"
          export TMUX_SLACK_LATER_WORKSPACE=${lib.escapeShellArg cfg.workspace}
          exec ${pkgs.bash}/bin/bash ${./later.sh} widget "$@"
        '';
      };

      # Same profile and workspace as refresh, deliberately: a list scoped
      # differently from the count it sits under would be a different inbox
      # wearing the same number.
      tmux-slack-later-list = pkgs.writeShellApplication {
        name = "tmux-slack-later-list";
        inherit runtimeInputs;
        text = ''
          export TMUX_SLACK_LATER_PROFILE="$HOME/.local/share/tmux-slack-later/chrome/Default"
          export TMUX_SLACK_LATER_WORKSPACE=${lib.escapeShellArg cfg.workspace}
          exec ${pkgs.bash}/bin/bash ${./later.sh} list "$@"
        '';
      };

      # The pane needs the workspace to decide which urls it is allowed to
      # hand to the desktop opener; it never reads the profile or the network.
      tmux-slack-later-pane = pkgs.writeShellApplication {
        name = "tmux-slack-later-pane";
        runtimeInputs = with pkgs; [
          coreutils
          fzf
          jq
          tmux-slack-later-list
          tmux-slack-later-refresh
        ];
        text = ''
          export TMUX_SLACK_LATER_WORKSPACE=${lib.escapeShellArg cfg.workspace}
          exec ${pkgs.bash}/bin/bash ${./later-pane.sh} "$@"
        '';
      };
    in
    {
      home.packages = lib.optionals userCfg.tmux.enable [
        tmux-slack-later-refresh
        tmux-slack-later-widget
        tmux-slack-later-list
        tmux-slack-later-pane
      ];

      # A real split, not a popup: the Later list is something you read while
      # working, and a popup dies the moment you touch the pane behind it.
      # Uppercase L only overrides tmux's default switch-client -l; lowercase l
      # stays lazygit's split. fzf owns the pane, so exiting fzf closes it —
      # nothing here kills a pane.
      programs.tmux.extraConfig = lib.mkIf userCfg.tmux.enable ''
        bind-key L split-window -h -p 40 '${tmux-slack-later-pane}/bin/tmux-slack-later-pane'
      '';

      # 47 keeps it beside the other attention counts — PR (45) and todoist
      # (46) — and left of the machine gauges, cpu (50) and disk (55).
      xdg.configFile."tmux/widgets/47-slack" = lib.mkIf userCfg.tmux.enable {
        executable = true;
        text = ''
          #!/usr/bin/env bash
          exec ${tmux-slack-later-widget}/bin/tmux-slack-later-widget "$@"
        '';
      };
    };
}
