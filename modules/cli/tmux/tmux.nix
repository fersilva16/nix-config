{
  mkUserModule,
  forPlatform,
  pkgs,
  lib,
  ...
}:
let
  # Copy-mode clipboard: pbcopy on darwin, wl-copy on linux (niri is the
  # only session — Wayland everywhere).
  tmux-clipboard = forPlatform {
    darwin = "pbcopy";
    linux = "${pkgs.wl-clipboard}/bin/wl-copy";
  };

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

  # Move the session's nvim window to the end. Renumber preserves relative
  # order, so shifting it past everything and letting tmux compact leaves it
  # last with the real windows contiguous at 1..N-1.
  tmux-nvim-park = pkgs.writeShellApplication {
    name = "tmux-nvim-park";
    runtimeInputs = [ pkgs.tmux ];
    text = ''
      session="''${1:-}"
      [ -n "$session" ] || exit 0
      win=$(tmux list-windows -t "$session" -f '#{==:#{@nvim_window},1}' -F '#{window_id}' 2>/dev/null | head -1)
      [ -n "$win" ] || exit 0
      tmux move-window -d -s "$win" -t "$session:9999" 2>/dev/null || true
      tmux move-window -r -t "$session" 2>/dev/null || true
    '';
  };

  # Focus (or create) a persistent nvim window for the current tmux session,
  # kept as the last window by tmux-nvim-park so it never takes a prefix+N slot
  # a real window wants. It stays an ordinary window, so prefix+2 and friends
  # work normally from inside it.
  #
  # It is tagged with an @nvim_window option rather than named: the status bar
  # hides tagged windows from the window list and draws the icon in status-left
  # instead, so it reads as a session-level fixture.
  tmux-nvim-window = pkgs.writeShellApplication {
    name = "tmux-nvim-window";
    runtimeInputs = [
      pkgs.tmux
      tmux-git-root-path
      tmux-nvim-park
    ];
    text = ''
      if [ -n "''${TMUX:-}" ]; then
        session=$(tmux display-message -p '#S')
      else
        # Most recently active client's session, falling back to the most
        # recently attached session so this still resolves when the server is
        # up but no client has registered yet. `|| true` keeps a missing tmux
        # server from tripping errexit.
        session=$(tmux list-clients -F '#{client_activity}|#{client_session}' 2>/dev/null | sort -rn | head -1 | cut -d'|' -f2 || true)
        [ -n "$session" ] || session=$(tmux list-sessions -F '#{session_last_attached}|#{session_name}' 2>/dev/null | sort -rn | head -1 | cut -d'|' -f2 || true)
      fi
      # ponytail: no retry loop — on a cold Ghostty launch the tmux server may
      # not exist yet, so this no-ops and a second Hyper+C works. Add a bounded
      # retry here if that ever gets annoying.
      if [ -z "$session" ]; then exit 0; fi

      active=$(tmux display-message -p -t "$session" '#{@nvim_window}' 2>/dev/null || true)
      if [ "$active" = "1" ]; then
        if [ "$(tmux display-message -p -t "$session" '#{pane_dead}' 2>/dev/null || true)" = "1" ]; then
          tmux respawn-window -k -t "$session" nvim
        else
          tmux last-window -t "$session" 2>/dev/null || true
        fi
        exit 0
      fi

      win=$(tmux list-windows -t "$session" -f '#{==:#{@nvim_window},1}' -F '#{window_id}' 2>/dev/null | head -1)
      if [ -n "$win" ]; then
        if [ "$(tmux display-message -p -t "$win" '#{pane_dead}' 2>/dev/null || true)" = "1" ]; then
          tmux respawn-window -k -t "$win" nvim
        fi
        tmux select-window -t "$win"
        exit 0
      fi

      pane_path=$(tmux display-message -p -t "$session" '#{pane_current_path}' 2>/dev/null || echo "$HOME")
      root=$(tmux-git-root-path "$pane_path")
      win=$(tmux new-window -d -t "$session:" -c "$root" -P -F '#{window_id}' nvim)
      tmux set-option -w -t "$win" @nvim_window 1
      # remain-on-exit keeps a crashed nvim's output on screen instead of the
      # window vanishing; Hyper+C respawns nvim into it.
      tmux set-option -w -t "$win" remain-on-exit on
      tmux-nvim-park "$session"
      tmux select-window -t "$win"
    '';
  };

  # Session picker rules, shared by the choose-tree binds here and in
  # session-picker.nix: sessions only, zoomed, sorted by name (worktree sessions
  # stay grouped with parent), and the `pocket` session filtered out (see
  # pocket.nix — pocket is popup-only, never selected via a picker; the
  # filter is a no-op when pocket is disabled).
  choose-tree-picker = "choose-tree -sZO name -f '#{!=:#{session_name},pocket}'";
in
mkUserModule {
  name = "tmux";
  parts = {
    theme = import ./theme.nix { inherit pkgs; };
    cheatsheet = import ./cheatsheet.nix { inherit pkgs; };
    statusbar = import ./statusbar.nix { inherit pkgs; };
    remote = import ./remote.nix { inherit pkgs; };
    group = import ./group.nix { inherit pkgs forPlatform; };
    pocket = import ./pocket.nix { inherit pkgs; };
    session-picker = import ./session-picker.nix { inherit pkgs choose-tree-picker; };
  };
  home =
    { cfg, userCfg, ... }:
    {
      home.packages = [
        tmux-git-root-path
        tmux-attach
        tmux-nvim-window
        tmux-nvim-park
      ];

      # Outbound: configure ghostty to auto-attach tmux
      programs.ghostty.settings.command = lib.mkIf userCfg.ghostty.enable "${tmux-attach}/bin/tmux-attach";

      programs.tmux = {
        enable = true;
        # default-shell is the wrapper tmux uses to run jobs — display-popup
        # -E, run-shell, if-shell all exec `default-shell -c cmd`
        # (JOB_DEFAULTSHELL in tmux's job.c). With fish here, every popup
        # sourced fish's config (~30ms measured) before running its command,
        # making popups feel laggy next to the in-process display-menu. Use a
        # bare POSIX sh (~5ms) for the job wrapper; interactive panes still get
        # login fish via default-command below.
        shell = "/bin/sh";
        prefix = "C-space";
        terminal = "screen-256color";
        keyMode = "vi";
        mouse = true;
        baseIndex = 1;
        historyLimit = 50000;
        sensibleOnTop = false;
        extraConfig = ''
          # New interactive panes launch login fish (default-shell is /bin/sh
          # for fast popup/run-shell jobs — see the shell option above). Pane
          # creation is rare, so the extra sh -c wrapper is irrelevant.
          set -g default-command "${pkgs.fish}/bin/fish -l"

          set -g renumber-windows on

          # Renumber compacts every window with no way to exempt one, so the
          # nvim window can't just sit at a high index — it gets dragged back
          # among the real windows. Instead, re-park it last whenever a window
          # is created; renumber preserves order, so it stays last from then on
          # and the real windows keep a contiguous 1..N-1.
          set-hook -g after-new-window 'run-shell -b "${tmux-nvim-park}/bin/tmux-nvim-park \"#{session_name}\""'
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
          bind-key -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel "${tmux-clipboard}"
          bind-key -T copy-mode-vi y send-keys -X copy-pipe-and-cancel "${tmux-clipboard}"

          # Reload config with prefix + R
          bind-key R source-file ~/.config/tmux/tmux.conf \; display-message "Config reloaded"

          # New windows open at nearest git root; panes inherit current directory
          bind-key c run-shell 'tmux new-window -c "$(${tmux-git-root-path}/bin/tmux-git-root-path "#{pane_current_path}")"'
          bind-key '"' split-window -c "#{pane_current_path}"
          bind-key % split-window -h -c "#{pane_current_path}"

          # Session picker. When the session-picker part is enabled it owns
          # prefix+s (fzf popup) and keeps choose-tree on prefix+S; otherwise
          # choose-tree stays on prefix+s. Conditional rather than rebinding to
          # avoid relying on part/parent extraConfig merge order.
          ${lib.optionalString (!cfg.session-picker.enable) "bind-key s ${choose-tree-picker}"}
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
