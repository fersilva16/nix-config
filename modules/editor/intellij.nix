{ mkUserModule, ... }:
mkUserModule {
  name = "intellij";
  casks = [ "intellij-idea-ce" ];
}
