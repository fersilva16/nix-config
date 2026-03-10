{ pkgs }:
pkgs.stdenvNoCC.mkDerivation {
  pname = "tmux-extras";
  version = "1.0.0";

  src = ./.;

  nativeBuildInputs = [ pkgs.makeWrapper ];

  dontBuild = true;

  installPhase = ''
    mkdir -p $out/bin
    cp git-status.sh $out/bin/tmux-git-status
    cp path-widget.sh $out/bin/tmux-path-widget
    cp cheatsheet.sh $out/bin/tmux-cheatsheet
    cp notify.sh $out/bin/tmux-notify
    cp notify-panel.sh $out/bin/tmux-notify-panel
    cp notify-widget.sh $out/bin/tmux-notify-widget
    chmod +x $out/bin/*

    # Wrap notification scripts to ensure dependencies are on PATH
    wrapProgram $out/bin/tmux-notify \
      --prefix PATH : ${
        pkgs.lib.makeBinPath [
          pkgs.jq
          pkgs.coreutils
          pkgs.tmux
        ]
      } \
      --prefix PATH : $out/bin
    wrapProgram $out/bin/tmux-notify-panel \
      --prefix PATH : ${
        pkgs.lib.makeBinPath [
          pkgs.jq
          pkgs.coreutils
          pkgs.ncurses
        ]
      } \
      --prefix PATH : $out/bin
    wrapProgram $out/bin/tmux-notify-widget \
      --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.jq ]}
  '';

  meta = {
    description = "Custom tmux status bar widgets, cheatsheet, and notification system";
  };
}
