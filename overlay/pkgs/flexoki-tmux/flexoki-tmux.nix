{ pkgs }:
pkgs.tmuxPlugins.mkTmuxPlugin {
  pluginName = "flexoki-tmux";
  version = "2.0.0";
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
    rev = "8d723bac4a9ac46adfdf99d42155286977aac72a";
    sha256 = "sha256-IxnvoZ9hGEvwq/PBbHTL5L2a2kxMSXSINIfd5Dg9ttA=";
  };
}
