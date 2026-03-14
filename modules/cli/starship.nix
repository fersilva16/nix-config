{ username, ... }:
{
  home-manager.users.${username} = {
    programs.starship = {
      enable = true;

      settings = {
        # Position worktree prefix before directory, then all default modules
        format = "\${custom.worktree}$all";

        character = {
          success_symbol = "[λ](bold green)";
          error_symbol = "[λ](bold red)";
          vicmd_symbol = "[λ](bold blue)";
        };

        nix_shell = {
          format = "via [$symbol]($style) ";
          symbol = " ";
        };

        custom.worktree = {
          command = "basename (dirname (git rev-parse --show-toplevel)) | string replace '.worktrees' ''";
          when = "string match -q '*.worktrees*' (git rev-parse --show-toplevel 2>/dev/null)";
          format = "[$output/]()";
          shell = [ "fish" ];
        };

        aws.disabled = true;
        gcloud.disabled = true;
      };
    };
  };
}
