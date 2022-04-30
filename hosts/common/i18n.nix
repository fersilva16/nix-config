{ pkgs, ... }:
{
  i18n.defaultLocale = pkgs.lib.mkDefault "en_US.UTF-8";
}
