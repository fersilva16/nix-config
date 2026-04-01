{
  mkUserModule,
  pkgs,
  lib,
  ...
}:
let
  inherit (pkgs) lib;
  baseSettings = {
    format = "\${custom.worktree}$all";

    nix_shell = {
      format = "via [$symbol]($style) ";
      symbol = " ";
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

  plainSettings = {
    format = "$directory\n$character";

    character = {
      success_symbol = "[>](bold green)";
      error_symbol = "[x](bold red)";
      vicmd_symbol = "[<](bold blue)";
    };

    directory.truncation_length = 1;
  };

  nerdSymbols = {
    character = {
      success_symbol = "[λ](bold green)";
      error_symbol = "[λ](bold red)";
      vicmd_symbol = "[λ](bold blue)";
    };
    nix_shell.symbol = " ";
  };
in
mkUserModule {
  name = "starship";
  home =
    { userCfg, ... }:
    {
      xdg.configFile."starship-plain.toml".source =
        (pkgs.formats.toml { }).generate "starship-plain.toml"
          plainSettings;

      programs.starship = {
        enable = true;
        settings = lib.recursiveUpdate baseSettings nerdSymbols;
      };

      # Fish shell integration: switch to plain config when tmux remote mode is active
      programs.fish.interactiveShellInit = lib.mkIf userCfg.fish.enable ''
        function __starship_remote_check --on-event fish_prompt
            if test -f /tmp/tmux-remote-state
                set -gx STARSHIP_CONFIG ~/.config/starship-plain.toml
            else
                set -ge STARSHIP_CONFIG
            end
        end
      '';
    };
}
