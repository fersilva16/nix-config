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
    # If zoxide returns a path rooted in ANY other worktree (main repo or
    # sibling worktree) and the equivalent path exists under the current
    # worktree, cd there instead. Falls back to the original result otherwise.
    programs.fish.interactiveShellInit = lib.mkAfter ''
      functions -q cd; and functions -c cd __zoxide_original_cd
      function cd --wraps=__zoxide_original_cd
        if test (count $argv) -gt 0; and test "$argv[1]" != -; and not test -d "$argv[1]"
          set -l result (command zoxide query --exclude (__zoxide_pwd) -- $argv 2>/dev/null)
          if test $status -eq 0
            set -l current_root (git rev-parse --show-toplevel 2>/dev/null)
            if test -n "$current_root"
              set -l worktrees (git worktree list --porcelain 2>/dev/null | string match 'worktree *' | string replace 'worktree ' "")
              for wt in $worktrees
                test "$wt" = "$current_root"; and continue
                set -l remapped (string replace "$wt/" "$current_root/" "$result")
                if test "$remapped" != "$result" -a -d "$remapped"
                  __zoxide_cd $remapped
                  return
                end
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
