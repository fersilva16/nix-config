{ mkUserModule, lib, ... }:
mkUserModule {
  name = "zoxide";
  home = {
    programs.zoxide = {
      enable = true;

      enableFishIntegration = true;

      options = [
        "--cmd=cd"
      ];
    };

    # Worktree-aware zoxide: remap results into the current worktree.
    # If zoxide returns /repo/ui (high rank from main repo usage) and
    # we're in /repo.worktrees/branch/, remap to /repo.worktrees/branch/ui
    # when that directory exists. Falls back to the original result otherwise.
    programs.fish.interactiveShellInit = lib.mkAfter ''
      functions -q cd; and functions -c cd __zoxide_original_cd
      function cd --wraps=__zoxide_original_cd
        if test (count $argv) -gt 0; and test "$argv[1]" != -; and not test -d "$argv[1]"
          set -l result (command zoxide query --exclude (__zoxide_pwd) -- $argv 2>/dev/null)
          if test $status -eq 0
            set -l current_root (git rev-parse --show-toplevel 2>/dev/null)
            set -l main_root (git worktree list --porcelain 2>/dev/null | head -1 | string replace "worktree " "")
            if test -n "$current_root" -a -n "$main_root" -a "$current_root" != "$main_root"
              set -l remapped (string replace "$main_root/" "$current_root/" "$result")
              if test "$remapped" != "$result" -a -d "$remapped"
                __zoxide_cd $remapped
                return
              end
            end
            __zoxide_cd $result
            return
          end
        end
        __zoxide_original_cd $argv
      end
    '';
  };
}
