{
  mkUserModule,
  pkgs,
  lib,
  ...
}:
let
  tmux-git-root-path = pkgs.writeShellApplication {
    name = "tmux-git-root-path";
    runtimeInputs = [ pkgs.git ];
    text = ''
      dir="''${1:-.}"
      cd "$dir" && git rev-parse --show-toplevel 2>/dev/null || echo "$dir"
    '';
  };

  tmux-attach = pkgs.writeShellApplication {
    name = "tmux-attach";
    bashOptions = [ ];
    runtimeInputs = [ pkgs.tmux ];
    text = ''
      SESSION=$(tmux list-sessions -F "#{session_name}" 2>/dev/null | head -1)
      if [ -z "$SESSION" ]; then
        exec tmux new-session -s main
      fi
      exec tmux attach-session -t "$SESSION"
    '';
  };
in
mkUserModule {
  name = "tmux";
  parts = {
    theme = import ./theme.nix { inherit pkgs; };
    cheatsheet = import ./cheatsheet.nix { inherit pkgs; };
    statusbar = import ./statusbar.nix { inherit pkgs; };
    opencode = import ./opencode.nix { inherit pkgs lib tmux-git-root-path; };
    remote = import ./remote.nix { inherit pkgs; };
    group = import ./group.nix { inherit pkgs; };
  };
  home =
    { userCfg, ... }:
    {
      home.packages = [
        tmux-git-root-path
        tmux-attach
      ];

      # Outbound: configure ghostty to auto-attach tmux
      programs.ghostty.settings.command = lib.mkIf userCfg.ghostty.enable "${tmux-attach}/bin/tmux-attach";

      programs.tmux = {
        enable = true;
        shell = "${pkgs.fish}/bin/fish";
        prefix = "C-space";
        terminal = "screen-256color";
        keyMode = "vi";
        mouse = true;
        baseIndex = 1;
        historyLimit = 50000;
        sensibleOnTop = false;
        extraConfig = ''
          set -g renumber-windows on
          set -g  escape-time 1
          set -g display-time 4000
          set -g status-interval 5
          set -g focus-events on
          setw -g aggressive-resize on
          set -ga terminal-overrides ",*-256color*:Tc"

          # Pass through extended keys (CSI u / kitty keyboard protocol)
          # Required for Cmd+P, Cmd+Shift+F etc. from Ghostty → tmux → nvim
          set -g extended-keys on
          set -g allow-passthrough on

          # Copy to system clipboard from vi copy mode
          bind-key -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel "pbcopy"
          bind-key -T copy-mode-vi y send-keys -X copy-pipe-and-cancel "pbcopy"

          # Reload config with prefix + R
          bind-key R source-file ~/.config/tmux/tmux.conf \; display-message "Config reloaded"

          # Open opencode in a new pane at nearest git root
          bind-key o run-shell 'tmux split-window -h -c "$(${tmux-git-root-path}/bin/tmux-git-root-path "#{pane_current_path}")" opencode'

          # Open lazygit in a new pane at nearest git root
          bind-key l run-shell 'tmux split-window -h -c "$(${tmux-git-root-path}/bin/tmux-git-root-path "#{pane_current_path}")" lazygit'

          # New windows open at nearest git root; panes inherit current directory
          bind-key c run-shell 'tmux new-window -c "$(${tmux-git-root-path}/bin/tmux-git-root-path "#{pane_current_path}")"'
          bind-key '"' split-window -c "#{pane_current_path}"
          bind-key % split-window -h -c "#{pane_current_path}"

          # Session picker sorted by name (worktree sessions stay grouped with parent)
          bind-key s choose-tree -sZO name
        '';

        plugins = with pkgs; [
          tmuxPlugins.better-mouse-mode
          {
            plugin = tmuxPlugins.resurrect;
            extraConfig = ''
              set -g @resurrect-capture-pane-contents 'on'
              set -g @resurrect-strategy-nvim 'session'
              set -g @resurrect-restore-cwd 'on'
            '';
          }
          {
            plugin = tmuxPlugins.continuum;
            extraConfig = ''
              set -g @continuum-restore 'on'
              set -g @continuum-save-interval '10'
            '';
          }
        ];
      };
    };
}
