{ pkgs }:
let
  tmux-cheatsheet = pkgs.writeShellApplication {
    name = "tmux-cheatsheet";
    bashOptions = [ ];
    runtimeInputs = [ pkgs.ncurses ];
    text = builtins.readFile ./scripts/cheatsheet.sh;
  };
in
{
  home = {
    home.packages = [ tmux-cheatsheet ];
    programs.tmux.extraConfig = ''
      # Cheatsheet popup on prefix + ?
      bind-key '?' display-popup -w 64 -h 80% -E "${tmux-cheatsheet}/bin/tmux-cheatsheet"
    '';
  };
}
