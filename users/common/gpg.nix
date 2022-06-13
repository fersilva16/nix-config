_:
{
  services.gpg-agent = {
    enable = true;

    pinentryFlavor = "tty";

    defaultCacheTtl = 86400;
    maxCacheTtl = 86400;

    extraConfig = ''
      allow-emacs-pinentry
    '';
  };
}
