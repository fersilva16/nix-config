{ pkgs, lib }:
let
  agents = "${
    pkgs.writeShellApplication {
      name = "tmux-resurrect-agents";
      text = builtins.readFile ./resurrect-agents.sh;
    }
  }/bin/tmux-resurrect-agents";
in
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
          # per-pane args, so match the binary name and resume the pane's own
          # session (saved from @oc-sid, see resurrect-agents.sh) instead of
          # replaying a path that a rebuild may have removed. `( |$)` keeps
          # e.g. `nvim …/omo.nix` from matching.
          set -g @resurrect-processes '"~/omo( |$)->${agents} resume omo" "~/opencode( |$)->${agents} resume opencode"'
          # Hooks are eval'd inside resurrect's scripts, so $(last_resurrect_file)
          # expands there to its `last` symlink.
          set -g @resurrect-hook-post-save-all '${agents} save "$(last_resurrect_file)"'
          set -g @resurrect-hook-pre-restore-pane-processes '${agents} restore "$(last_resurrect_file)"'
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
