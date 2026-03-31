{ mkUserModule, ... }:
mkUserModule {
  name = "tailscale";
  system.homebrew.casks = [ "tailscale-app" ];
}
