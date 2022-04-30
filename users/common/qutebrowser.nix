{ lib, ... }:
{
  programs.qutebrowser = {
    enable = true;
  };

  xdg.mimeApps.defaultApplications = lib.genAttrs [
    "x-scheme-handler/qute"
  ]
    (_: [ "org.qutebrowser.qutebrowser.desktop" ]);
}
