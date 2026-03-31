{ mkUserModule, ... }:
mkUserModule {
  name = "word";
  system.homebrew.casks = [ "microsoft-word" ];
}
