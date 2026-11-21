# Forza Horizon 1: ReImagined — the 2012 Xbox 360 game statically recompiled
# to native x86-64. The release ships only the launcher; it builds the game
# from your own disc image into ~/.local/share/forza (game files, toolchain,
# saves), so nothing here touches that state.
#
# Linux only (the project has no macOS launcher). The launcher is a
# PyInstaller binary and compiles C++23 with a clang it downloads, which
# needs an FHS root with libstdc++ headers, GCC's crt files and `ld`:
# steam-run plus those. Its self-updater cannot write to the store, so
# update by bumping `version` and `hash`.
{
  mkUserModule,
  forPlatform,
  pkgs,
  lib,
  ...
}:
let
  version = "0.3.8";
  launcher = pkgs.fetchzip {
    url = "https://github.com/FH1-ReImagined/ForzaHorizon1-ReImagined/releases/download/v${version}/ForzaHorizon1-ReImagined-linux-x86_64.tar.gz";
    hash = "sha256-9jKMnlKxWzC/r4UDdLNynwZNLjczIXZ0v6TRWc8sSdI=";
  };
  fhs =
    (pkgs.steam.override {
      extraPkgs = p: [
        p.gcc.cc # /usr/include/c++ and /usr/lib/gcc crt files
        p.gcc.cc.lib
        p.glibc.dev
        p.linuxHeaders
        p.binutils-unwrapped # ld: the launcher probes with a clean PATH
      ];
    }).run;
in
mkUserModule {
  name = "forza-horizon";
  home =
    { userCfg, ... }:
    let
      # With steam's GameMode daemon, the game runs in GameMode and takes
      # the machine (modules/games/steam.nix). gamemoderun goes inside
      # steam-run, whose sandbox would drop the library path it sets.
      gamemoderun = lib.optionalString userCfg.steam.enable "${pkgs.gamemode}/bin/gamemoderun ";
      forza-reimagined = pkgs.writeShellScriptBin "forza-reimagined" ''
        exec ${fhs}/bin/steam-run ${gamemoderun}${launcher}/forza-launcher "$@"
      '';
    in
    {
      home.packages = forPlatform { linux = [ forza-reimagined ]; };
      xdg.desktopEntries = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
        forza-reimagined = {
          name = "Forza Horizon 1: ReImagined";
          exec = "${forza-reimagined}/bin/forza-reimagined";
          icon = "${launcher}/forza-reimagined.png";
          categories = [ "Game" ];
          settings.StartupWMClass = "forza-reimagined";
        };
      };
    };
}
