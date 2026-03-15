{ username, pkgs, ... }:
{
  home-manager.users.${username} = {
    programs.lazygit = {
      enable = true;
      settings = {
        gui = {
          nerdFontsVersion = "3";
          theme = {
            activeBorderColor = [
              "#205EA6"
              "bold"
            ]; # blue
            inactiveBorderColor = [ "#CECDC3" ]; # ui-3
            optionsTextColor = [ "#205EA6" ]; # blue
            selectedLineBgColor = [ "#E6E4D9" ]; # ui
            selectedRangeBgColor = [ "#DAD8CE" ]; # ui-2
            cherryPickedCommitBgColor = [ "#24837B" ]; # cyan
            cherryPickedCommitFgColor = [ "#FFFCF0" ]; # paper
            unstagedChangesColor = [ "#AF3029" ]; # red
            defaultFgColor = [ "#100F0F" ]; # tx
          };
        };
      };
    };
  };
}
