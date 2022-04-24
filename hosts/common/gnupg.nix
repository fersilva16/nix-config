{
  programs.gnupg.agent = {
    enable = true;
    pinentryFlavor = "tty";
  };

  services.gnome.gnome-keyring.enable = true;
}
