{ lib, ... }:
{
  programs.qutebrowser = {
    enable = true;
  };

  xdg.mimeApps.defaultApplications = lib.genAttrs [
    "text/html"
    "text/xml"
    "x-scheme-handler/http"
    "x-scheme-handler/https"
    "x-scheme-handler/qute"
  ] (_: [ "org.qutebrowser.qutebrowser.desktop" ]);
}
