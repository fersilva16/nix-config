{
  mkUserModule,
  pkgs,
  lib,
  ...
}:
let
  mohak34-sounds = pkgs.stdenvNoCC.mkDerivation {
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

  tmux-opencode-manager = pkgs.writeShellApplication {
    name = "tmux-opencode-manager";
    bashOptions = [ ];
    runtimeInputs = [
      pkgs.argc
      pkgs.jq
      pkgs.tmux
      pkgs.coreutils
      pkgs.gawk
    ];
    text = builtins.readFile ./scripts/opencode-manager.sh;
  };
in
mkUserModule {
  name = "opencode-manager";
  requires = [
    "tmux"
    "opencode"
  ];
  home = {
    home.packages = [
      tmux-opencode-manager
    ];

    xdg.configFile = {
      "tmux/widgets/10-notify" = {
        executable = true;
        text = ''
          #!/usr/bin/env bash
          exec ${tmux-opencode-manager}/bin/tmux-opencode-manager widget
        '';
      };

      "opencode/plugin/tmux-notifier.ts".source = ./plugins/tmux-notifier.ts;

      # `types.lines`: agents with their own notifier append their
      # #{pane_current_command} pattern (see scripts/opencode-manager.sh).
      "tmux-opencode-manager/agent-commands".text = "opencode";
    };

    home.sessionVariables.OPENCODE_TMUX_NOTIFIER_SOUND_DIR = "${mohak34-sounds}";

    programs.tmux.extraConfig = ''
      # prefix+N drains the notification queue: jumps to the most recent
      # notification's window and dismisses it, so pressing it repeatedly walks
      # every pending one. This replaced a `prefix+n` browse-all popup — the
      # session picker (cli/tmux/session-picker.nix) already shows the same
      # per-session attention glyph from the same source, and worktree-per-topic
      # keeps sessions ~1:1 with opencode panes, so a second picker earned
      # nothing.
      bind-key 'N' run-shell -b "env TMUX_OPENCODE_CALLER_TTY='#{client_tty}' ${tmux-opencode-manager}/bin/tmux-opencode-manager notify goto"
      set-hook -g after-select-window 'run-shell -b "${tmux-opencode-manager}/bin/tmux-opencode-manager notify dismiss-target #{session_name}:#{window_index}"'
      set-hook -g client-session-changed 'run-shell -b "${tmux-opencode-manager}/bin/tmux-opencode-manager notify dismiss-target #{session_name}:#{window_index}"'
      set-hook -g after-kill-pane 'run-shell -b "${tmux-opencode-manager}/bin/tmux-opencode-manager notify dismiss-pane \"#{hook_arguments}\""'
      set-hook -g session-closed 'run-shell -b "${tmux-opencode-manager}/bin/tmux-opencode-manager notify dismiss-session #{session_name}"'
    '';
  };
}
