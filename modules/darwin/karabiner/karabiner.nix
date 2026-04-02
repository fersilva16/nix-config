{ mkUserModule, ... }:
mkUserModule {
  name = "karabiner";
  system.homebrew.casks = [ "karabiner-elements" ];
  home = {
    home.file.".config/karabiner/karabiner.json" = {
      source = ./karabiner.json;
      force = true;
    };
  };
}
