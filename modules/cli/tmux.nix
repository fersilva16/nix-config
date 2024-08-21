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
      extraConfig = ''
        set -ga terminal-overrides ",xterm-256color*:Tc"

        bind-key h select-pane -L
        bind-key j select-pane -D
        bind-key k select-pane -U
        bind-key l select-pane -R
      '';

      plugins = with pkgs; [
        tmuxPlugins.catppuccin
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
            set -g @continuum-boot 'on'
            set -g @continuum-save-interval '10'
          '';
        }
      ];
    };
  };
}
