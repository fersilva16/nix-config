# PS Remote Play: Sony's app on darwin; on linux, which Sony skips, chiaki-ng.
{
  mkUserModule,
  forPlatform,
  pkgs,
  ...
}:
let
  # The session's QT_STYLE_OVERRIDE (adwaita-dark, modules/linux/qt.nix) is a
  # widgets style; chiaki-ng loads it as a Qt Quick style it lacks, and its
  # window never opens.
  chiaki-ng = pkgs.symlinkJoin {
    name = "chiaki-ng";
    paths = [ pkgs.chiaki-ng ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = "wrapProgram $out/bin/chiaki --unset QT_STYLE_OVERRIDE";
  };
in
mkUserModule {
  name = "sony";
  casks = [ "sony-ps-remote-play" ];
  # chiaki-ng broadcasts its discovery from a UDP port in 9303-9319 and the
  # console answers that port by unicast, which conntrack cannot match to a
  # broadcast, so without this the PS5 never shows up in the host list.
  system = forPlatform {
    linux.networking.firewall.allowedUDPPortRanges = [
      {
        from = 9303;
        to = 9319;
      }
    ];
  };
  home.home.packages = forPlatform { linux = [ chiaki-ng ]; };
}
