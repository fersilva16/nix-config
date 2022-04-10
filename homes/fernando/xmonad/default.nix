{ pkgs, ... }: {
  xsession = {
    enable = true;

    initExtra = ''
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
