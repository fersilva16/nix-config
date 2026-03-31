{ mkUserModule, ... }:
mkUserModule {
  name = "obsidian";
  system.homebrew.casks = [ "obsidian" ];
}
