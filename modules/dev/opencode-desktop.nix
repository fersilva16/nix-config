{ mkUserModule, ... }:
mkUserModule {
  name = "opencode-desktop";
  system.homebrew.casks = [ "opencode-desktop" ];
}
