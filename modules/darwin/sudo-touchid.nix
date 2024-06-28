_:
{
  environment.etc = {
    "pam.d/sudo_local" = {
      text = ''
        auth       sufficient     pam_tid.so
      '';
    };
  };
}
