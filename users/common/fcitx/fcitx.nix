{ pkgs, config, ... }:
let
  replaceColors = import ../../../lib/replaceColors.nix { inherit config; };
in
{
  i18n.inputMethod = {
    enabled = "fcitx5";

    fcitx5.addons = with pkgs; [ fcitx5-mozc ];
  };

  # home.file.".config/fcitx5/config" = {
  #   source = config.lib.file.mkOutOfStoreSymlink ./config.ini;
  # };

  # home.file.".config/fcitx5/profile" = {
  #   source = config.lib.file.mkOutOfStoreSymlink ./profile.ini;
  # };

  home.file.".config/fcitx5/conf/classicui.conf" = {
    source = config.lib.file.mkOutOfStoreSymlink ./classicui.conf;
  };

  home.file.".local/share/fcitx5/themes/theme/theme.conf" = {
    text = replaceColors (builtins.readFile ./theme.conf);
  };
}
