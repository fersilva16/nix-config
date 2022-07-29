{ pkgs, ... }:
{
  i18n = {
    defaultLocale = pkgs.lib.mkDefault "en_US.UTF-8";


    inputMethod = {
      enabled = "fcitx";

      fcitx.engines = with pkgs.fcitx-engines; [ mozc ];
    };
  };
}
