{ mkUserModule, pkgs, ... }:
mkUserModule {
  name = "dconf";
  home = {
    home.packages = with pkgs; [ dconf ];
  };
}
