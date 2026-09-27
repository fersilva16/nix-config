{ pkgs, lib }:
{
  home.programs.tmux = {
    plugins = [
      {
        plugin = pkgs.tmuxPlugins.resurrect;
        extraConfig = ''
          set -g @resurrect-capture-pane-contents 'on'
          set -g @resurrect-strategy-nvim 'session'
          set -g @resurrect-restore-cwd 'on'
          # Agents are saved under their versioned store/runtime path with
          # per-pane args, so match the binary name and resume the cwd's last
          # session instead of replaying a path that a rebuild may have removed.
          # `( |$)` keeps e.g. `nvim …/omo.nix` from matching.
          set -g @resurrect-processes '"~/omo( |$)->omo --continue" "~/opencode( |$)->opencode --continue"'
        '';
      }
    ];

    # continuum saves by prepending `#(continuum_save.sh)` to status-right when
    # it loads. home-manager writes plugins before extraConfig, so as a plugin
    # its hook was overwritten by the statusbar part's `set -g status-right`
    # and auto-save never ran. mkAfter loads it after every status-right set.
    extraConfig = lib.mkAfter ''
      set -g @continuum-restore 'on'
      set -g @continuum-save-interval '10'
      run-shell ${pkgs.tmuxPlugins.continuum.rtp}
    '';
  };
}
