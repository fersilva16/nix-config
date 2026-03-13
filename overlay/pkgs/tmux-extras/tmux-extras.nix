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
    cp tmux-attach.sh $out/bin/tmux-attach
    cp tmux-group.sh $out/bin/tmux-group
    cp tmux-ungroup.sh $out/bin/tmux-ungroup
    cp remote.sh $out/bin/tmux-remote
    cp remote-widget.sh $out/bin/tmux-remote-widget
    cp battery-widget.sh $out/bin/tmux-battery-widget
    cp status-right.sh $out/bin/tmux-status-right
    cp git-root-path.sh $out/bin/tmux-git-root-path
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
    wrapProgram $out/bin/tmux-attach \
      --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.tmux ]}
    wrapProgram $out/bin/tmux-group \
      --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.tmux ]}
    wrapProgram $out/bin/tmux-ungroup \
      --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.tmux ]}
    wrapProgram $out/bin/tmux-remote \
      --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.tmux ]}
    wrapProgram $out/bin/tmux-status-right \
      --prefix PATH : ${
        pkgs.lib.makeBinPath [
          pkgs.jq
          pkgs.coreutils
        ]
      } \
      --prefix PATH : $out/bin
  '';

  meta = {
    description = "Custom tmux status bar widgets, cheatsheet, and notification system";
  };
}
