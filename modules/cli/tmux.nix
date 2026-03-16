{ username, pkgs, ... }:
let
  inherit (pkgs) tmux-extras;
in
{
  home-manager.users.${username} = {
    xdg.configFile."tmux/tmux-nerd-font-window-name.yml".text = ''
      config:
        fallback-icon: "?"
        show-name: false
        always-show-fallback-name: true

      icons:
        .opencode-wrapp: ""
        task: "󱓞"
    '';

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

        # Reload config with prefix + R
        bind-key R source-file ~/.config/tmux/tmux.conf \; display-message "Config reloaded"

        # Status bar right side (after all plugins to avoid being overwritten)
        # Uses a single script that switches between full/minimal bar based on remote mode
        set -g status-right "#(${tmux-extras}/bin/tmux-status-right #{pane_current_path})"
        set -g status-right-length 200

        # Cheatsheet popup on prefix + ?
        bind-key '?' display-popup -w 64 -h 80% -E "${tmux-extras}/bin/tmux-cheatsheet"

        # Notification panel on prefix + n
        bind-key 'n' display-popup -w 60 -h 20 -E "${tmux-extras}/bin/tmux-notify-panel"

        # Jump to last notification on prefix + N
        bind-key 'N' run-shell "${tmux-extras}/bin/tmux-notify goto"

        # Open opencode in a new pane at nearest git root
        bind-key o run-shell 'tmux split-window -h -c "$(${tmux-extras}/bin/tmux-git-root-path "#{pane_current_path}")" opencode'

        # Open lazygit in a new pane at nearest git root
        bind-key l run-shell 'tmux split-window -h -c "$(${tmux-extras}/bin/tmux-git-root-path "#{pane_current_path}")" lazygit'

        # New windows open at nearest git root; panes inherit current directory
        bind-key c run-shell 'tmux new-window -c "$(${tmux-extras}/bin/tmux-git-root-path "#{pane_current_path}")"'
        bind-key '"' split-window -c "#{pane_current_path}"
        bind-key % split-window -h -c "#{pane_current_path}"

        # Session picker sorted by name (worktree sessions stay grouped with parent)
        bind-key s choose-tree -sZO name

        # Group session (multi-monitor): prefix + g to create, prefix + G to leave
        bind-key 'g' run-shell "${tmux-extras}/bin/tmux-group"
        bind-key 'G' run-shell "${tmux-extras}/bin/tmux-ungroup"

        # Remote access mode: prefix + C-R to toggle (SSH + lid-close safe + battery saving)
        bind-key 'C-R' run-shell "${tmux-extras}/bin/tmux-remote toggle"
      '';

      plugins = with pkgs; [
        {
          plugin = flexoki-tmux;
        }
        tmuxPlugins.better-mouse-mode
        {
          plugin = tmux-nerd-font-window-name;
        }
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
