{ ... }:
{
  services.fprintd = {
    enable = true;
  };

  security.pam.services.login = {
    fprintAuth = true;
  };

  security.pam.services.xscreensaver = {
    fprintAuth = true;
  };
}
