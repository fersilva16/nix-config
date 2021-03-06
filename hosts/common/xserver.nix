_:
{
  services.xserver = {
    enable = true;
    layout = "br,us";
    xkbVariant = "abnt2,";

    videoDrivers = [ "nvidia" ];

    displayManager = {
      defaultSession = "xsession";

      autoLogin = {
        enable = true;
        user = "fernando";
      };

      session = [
        {
          name = "xsession";
          manage = "desktop";
          start = "exec $HOME/.xsession";
        }
      ];
    };
  };
}


