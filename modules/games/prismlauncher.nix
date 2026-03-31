{ mkUserModule, ... }:
mkUserModule {
  name = "prismlauncher";
  system.homebrew.casks = [ "prismlauncher" ];
}
