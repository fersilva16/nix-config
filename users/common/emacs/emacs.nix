{ config, ... }:
{
  programs.emacs = {
    enable = true;
  };

  home.file.".emacs.d/init.el" = {
    source = config.lib.file.mkOutOfStoreSymlink "/dotfiles/users/common/emacs/init.el";
  };
}
