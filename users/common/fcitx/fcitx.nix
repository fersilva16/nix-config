{ pkgs, config, ... }:
{
  i18n.inputMethod = {
    enabled = "fcitx5";

    fcitx5.addons = with pkgs; [ fcitx5-mozc ];
  };

  # home.file.".config/fcitx5/config" = {
  #   source = config.lib.file.mkOutOfStoreSymlink "/dotfiles/users/common/fcitx/config.ini";
  # };

  # home.file.".config/fcitx5/profile" = {
  #   source = config.lib.file.mkOutOfStoreSymlink "/dotfiles/users/common/fcitx/profile.ini";
  # };

  home.file.".config/fcitx5/conf/classicui.conf" = {
    source = config.lib.file.mkOutOfStoreSymlink "/dotfiles/users/common/fcitx/classicui.conf";
  };

  home.file.".local/share/fcitx5/themes/theme/theme.conf" = {
    text = builtins.readFile "/dotfiles/users/common/fcitx/theme.conf";
  };
}
