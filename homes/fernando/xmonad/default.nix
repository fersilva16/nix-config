{ pkgs, ... }: {
  xsession = {
    enable = true;

    initExtra = ''
      xrandr --output eDP-1-1 --mode 1920x1080 --rate 144 --primary
      xrandr --output HDMI-0 --mode 1920x1080  --rate 60 --left-of eDP-1-1

      keyctl link @u @s
    '';

    windowManager.xmonad = {
      enable = true;
      enableContribAndExtras = true;

      extraPackages = haskellPackages:
        with haskellPackages; [
          xmonad
          xmonad-contrib
          xmonad-extras
        ];

      config = ./config.hs;
    };
  };

  home.packages = with pkgs; [ dmenu ];
}
