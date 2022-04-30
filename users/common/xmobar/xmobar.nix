{ ... }:
{
  programs.xmobar = {
    enable = true;

    extraConfig = builtins.readFile ./xmobarrc;
  };
}
