# Screen recorder part — noctalia's official screen-recorder plugin
# (gpu-screen-recorder, NVENC-accelerated). It records through the screencast
# portal, so niri's picker chooses a monitor or a single window; recordings
# land in ~/Videos with a "saved" toast. Driven from the Cmd+Shift+5 capture
# menu in modules/linux/niri/niri.nix via its IPC target
# `plugin:screen-recorder`.
#
# Installed read-only from noctalia-plugins at the same commit the vendored
# polkit-agent came from, so its settings stay at the manifest defaults.
{ pkgs }:
let
  noctalia-plugins = pkgs.fetchFromGitHub {
    owner = "noctalia-dev";
    repo = "noctalia-plugins";
    rev = "ea21cb63d063075bc0acd72d8b946ce2c5eef00d";
    hash = "sha256-M+7SLW+wI3KvDMj8dSrW/uUmpPiYhsXA2jpbbgL5imk=";
  };
in
{
  home = {
    home.packages = [ pkgs.gpu-screen-recorder ];
    programs.noctalia-shell.plugins.states.screen-recorder = {
      enabled = true;
      sourceUrl = "local";
    };
    xdg.configFile."noctalia/plugins/screen-recorder".source = "${noctalia-plugins}/screen-recorder";
  };
}
