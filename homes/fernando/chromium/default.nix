{ ... }:
{
  programs.chromium = {
    enable = true;

    extensions = [
      {
        # uBlock Origin
        id = "cjpalhdlnbpafiamejdnhcphjbkeiagm";
      }
      {
        # Bitwarden
        id = "nngceckbapebfimnlniiiahkandclblb";
      }
      {
        # Phantom Wallet
        id = "bfnaelmomeimhlpmgjnjophhpkkoljpa";
      }
    ];
  };

  xdg.mimeApps.defaultApplications = lib.genAttrs [
    "text/html"
    "text/xml"
    "x-scheme-handler/http"
    "x-scheme-handler/https"
  ]
    (_: [ "chromium-browser.desktop" ]);
}
