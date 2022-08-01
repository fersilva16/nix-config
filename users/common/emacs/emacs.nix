{ config, ... }:
{
  programs.emacs = {
    enable = true;
  };

  home.file.".emacs.d/init.el" = {
    source = config.lib.file.mkOutOfStoreSymlink ./init.el;
  };
}
