# ~/Desktop, ~/Downloads, ~/Pictures, ... created and registered in
# user-dirs.dirs, so browsers, screenshots and the file manager agree on them.
{ mkUserModule, ... }:
mkUserModule {
  name = "xdg-user-dirs";
  home.xdg.userDirs = {
    enable = true;
    createDirectories = true;
  };
}
