{ ... }:
{
  services.xserver = {
    enable = true;
    layout = "br,us";
    xkbVariant = "abnt2,";

    videoDrivers = [ "intel" "nvidia" ];

    displayManager = {
      defaultSession = "xsession";

      session = [
        {
          name = "xsession";
          manage = "desktop";
          start = ''exec $HOME/.xsession'';
        }
      ];

      # startx.enable = true;
    };

    # Not sure if I need xmonad here when I'm using xsession
    # windowManager.xmonad = {
    #   enable = true;
    #   enableContribAndExtras = true;
    #   extraPackages = haskellPackages: with haskellPackages; [
    #     xmonad
    #     xmonad-contrib
    #     xmonad-extras
    #     xmobar
    #   ];
    # };
  };
}
