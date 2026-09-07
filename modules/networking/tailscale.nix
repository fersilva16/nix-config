# darwin runs the cask (its GUI owns the menu-bar state and the system
# extension); linux runs the daemon from nixpkgs. Joining is still a
# one-time manual `tailscale up` per host — no auth key lives in the repo.
{ mkUserModule, forPlatform, ... }:
mkUserModule {
  name = "tailscale";
  casks = [ "tailscale-app" ];
  system = forPlatform {
    linux.services.tailscale.enable = true;
  };
}
