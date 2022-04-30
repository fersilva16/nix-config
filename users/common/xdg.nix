_:
{
  xdg = {
    enable = true;

    mimeApps = {
      defaultApplications = {
        "text/html" = [ "chromium-browser.desktop" ];
        "text/xml" = [ "chromium-browser.desktop" ];
        "x-scheme-handler/http" = [ "chromium-browser.desktop" ];
        "x-scheme-handler/https" = [ "chromium-browser.desktop" ];
      };
    };
  };
}
