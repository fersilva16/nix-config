{ pkgs }:
pkgs.stdenvNoCC.mkDerivation {
  pname = "tmux-extras";
  version = "1.0.0";

  src = ./.;

  dontBuild = true;

  installPhase = ''
    mkdir -p $out/bin
    cp git-status.sh $out/bin/tmux-git-status
    cp path-widget.sh $out/bin/tmux-path-widget
    cp cheatsheet.sh $out/bin/tmux-cheatsheet
    chmod +x $out/bin/*
  '';

  meta = {
    description = "Custom tmux status bar widgets and cheatsheet";
  };
}
