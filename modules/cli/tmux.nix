{ username, pkgs, ... }:
{
  home-manager.users.${username} = {
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
        set -g  escape-time 1
        set -g display-time 4000
        set -g status-interval 5
        set -g focus-events on
        setw -g aggressive-resize on
        set -ga terminal-overrides ",*-256color*:Tc"
      '';

      plugins = with pkgs; [
        flexoki-tmux
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
