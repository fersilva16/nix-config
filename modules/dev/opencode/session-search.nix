{ pkgs }:
let
  tmux-oc-search = pkgs.writeShellApplication {
    name = "tmux-oc-search";
    runtimeInputs = with pkgs; [
      tmux
      fzf
      sqlite
      gawk
      gnugrep
      gnused
      coreutils
    ];
    text = builtins.readFile ./scripts/oc-search.sh;
  };
in
{
  home =
    { lib, userCfg, ... }:
    lib.mkIf userCfg.tmux.enable {
      home.packages = [ tmux-oc-search ];

      programs.tmux.extraConfig = ''
        # Search opencode session history. Reclaims prefix+n, which the
        # opencode-manager module freed when its browse-all popup became
        # prefix+N (drain the notification queue). Reading history and
        # answering "who needs me now" are different jobs; only the second
        # one wanted a queue.
        bind-key 'n' display-popup -E -w 70% -h 60% '${tmux-oc-search}/bin/tmux-oc-search'
      '';
    };
}
