{
  mkUserModule,
  forPlatform,
  pkgs,
  ...
}:
mkUserModule {
  name = "chrome";
  casks = [ "google-chrome" ];
  # Chrome is the primary browser (see firefox.nix), so on linux it is the
  # default for web links and PDFs. darwin routes links through finicky.
  home = forPlatform {
    linux = {
      home.packages = [ pkgs.google-chrome ];
      xdg.mimeApps = {
        enable = true;
        defaultApplications = {
          "text/html" = "google-chrome.desktop";
          "x-scheme-handler/http" = "google-chrome.desktop";
          "x-scheme-handler/https" = "google-chrome.desktop";
          "application/pdf" = "google-chrome.desktop";
        };
      };
      # Chrome rewrites mimeapps.list when it checks it is the default.
      xdg.configFile."mimeapps.list".force = true;
    };
  };
}
