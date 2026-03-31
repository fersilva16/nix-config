{ mkUserModule, ... }:
mkUserModule {
  name = "intellij";
  system.homebrew.casks = [ "intellij-idea-ce" ];
}
