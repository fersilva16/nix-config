{ pkgs }:
pkgs.tmuxPlugins.mkTmuxPlugin {
  pluginName = "flexoki-tmux";
  version = "unstable-2024-08-12";
  rtpFilePath = "flexoki.tmux";
  preInstall = ''
    cd tmux
    cp ${./flexoki-bar.conf} flexoki-bar.conf
    cp ${./flexoki.tmux} flexoki.tmux
    chmod +x flexoki.tmux
  '';

  src = pkgs.fetchFromGitHub {
    owner = "kepano";
    repo = "flexoki";
    rev = "06aa48fd34abc93c9229dc22274356ec03dd4a68";
    sha256 = "sha256-rAuOnr5E1TgLbMe5jrGSYh41VE6uM5ZoOmwXOYb4ftc=";
  };
}

