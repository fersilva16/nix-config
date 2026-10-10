# omo notifier part: each omo publishes its state as options on its tmux pane
# (tmux-notifier.ts), and tmux reads them back (tmux-agent-notify.sh): the
# status-bar pill, prefix+N, and clearing attention once you look. The bar's
# busy colour (cli/tmux), the session picker and wts read the same options.
{ pkgs, lib }:
let
  sounds = pkgs.stdenvNoCC.mkDerivation {
    pname = "mohak34-opencode-notifier-sounds";
    version = "0.1.36";
    src = pkgs.fetchFromGitHub {
      owner = "mohak34";
      repo = "opencode-notifier";
      rev = "v0.1.36";
      sha256 = "sha256-tjxaqh9akN81MMToeGG1wNEiTp0/WEOmatmXewCThWU=";
    };
    dontBuild = true;
    installPhase = ''
      mkdir -p $out
      cp sounds/*.wav $out/
    '';
  };

  tmux-agent-notify = pkgs.writeShellApplication {
    name = "tmux-agent-notify";
    runtimeInputs = [
      pkgs.tmux
      pkgs.coreutils
      pkgs.gawk
    ];
    text = builtins.readFile ./tmux-agent-notify.sh;
  };
  notify = "${tmux-agent-notify}/bin/tmux-agent-notify";
in
{
  home =
    { userCfg, ... }:
    lib.mkIf userCfg.tmux.enable {
      home.file.".omo/agent/extensions/tmux-notifier.ts".source = pkgs.replaceVars ./tmux-notifier.ts {
        soundDir = sounds;
      };

      xdg.configFile."tmux/widgets/10-notify" = {
        executable = true;
        text = ''
          #!/usr/bin/env bash
          exec ${notify} widget
        '';
      };

      programs.tmux.extraConfig = ''
        # prefix+N jumps to the newest omo pane that needs you and clears it;
        # press again to walk the rest. Looking at a window clears it too.
        bind-key 'N' run-shell -b "${notify} goto '#{client_tty}'"
        set-hook -g after-select-window 'run-shell -b "${notify} dismiss #{window_id}"'
        set-hook -g client-session-changed 'run-shell -b "${notify} dismiss #{window_id}"'
      '';
    };
}
