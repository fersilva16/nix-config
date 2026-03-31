{ mkUserModule, pkgs, ... }:
mkUserModule {
  name = "linear";
  system.homebrew.casks = [ "linear-linear" ];
  home = {
    home.packages = with pkgs; [
      linear-cli
      gum
      jq
    ];
  };
}
