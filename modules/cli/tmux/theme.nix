{ pkgs }:
let
  flexoki-tmux = pkgs.tmuxPlugins.mkTmuxPlugin {
    pluginName = "flexoki-tmux";
    version = "2.0.0";
    rtpFilePath = "flexoki.tmux";
    preInstall = ''
      cd tmux
      cp ${./scripts/flexoki-bar.conf} flexoki-bar.conf
      cp ${./scripts/flexoki.tmux} flexoki.tmux
      chmod +x flexoki.tmux
    '';

    src = pkgs.fetchFromGitHub {
      owner = "kepano";
      repo = "flexoki";
      rev = "8d723bac4a9ac46adfdf99d42155286977aac72a";
      sha256 = "sha256-IxnvoZ9hGEvwq/PBbHTL5L2a2kxMSXSINIfd5Dg9ttA=";
    };
  };

  tmux-nerd-font-window-name = pkgs.tmuxPlugins.mkTmuxPlugin {
    pluginName = "tmux-nerd-font-window-name";
    version = "2.3.0-unstable-2026-02-17";
    rtpFilePath = "tmux-nerd-font-window-name.tmux";

    src = pkgs.fetchFromGitHub {
      owner = "joshmedeski";
      repo = "tmux-nerd-font-window-name";
      rev = "7c08b6be2a1d0502d5c5cc7171f8507502ca3e25";
      sha256 = "sha256-i3DT+r7WUvutRhob+tHZOe8TBUxpe4JflS9e1dgkg6s=";
    };
  };
in
{
  home = {
    xdg.configFile."tmux/tmux-nerd-font-window-name.yml".text = ''
      config:
        fallback-icon: "?"
        show-name: false
        always-show-fallback-name: true

      icons:
        .opencode-wrapp: ""
        task: "󱓞"
        agents: "󰚩"
    '';

    programs.tmux.plugins = [
      { plugin = flexoki-tmux; }
      { plugin = tmux-nerd-font-window-name; }
    ];
  };
}
