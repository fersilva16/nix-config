{ mkUserModule, ... }:
mkUserModule {
  name = "tailscale";
  casks = [ "tailscale-app" ];
}
