{ pkgs }:
pkgs.tmuxPlugins.mkTmuxPlugin {
  pluginName = "tmux-nerd-font-window-name";
  version = "2.3.0-unstable-2026-02-17";
  rtpFilePath = "tmux-nerd-font-window-name.tmux";

  src = pkgs.fetchFromGitHub {
    owner = "joshmedeski";
    repo = "tmux-nerd-font-window-name";
    rev = "7c08b6be2a1d0502d5c5cc7171f8507502ca3e25";
    sha256 = "sha256-i3DT+r7WUvutRhob+tHZOe8TBUxpe4JflS9e1dgkg6s=";
  };
}
