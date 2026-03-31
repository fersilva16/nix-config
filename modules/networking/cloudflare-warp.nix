{ mkUserModule, ... }:
mkUserModule {
  name = "cloudflare-warp";
  system.homebrew.casks = [ "cloudflare-warp" ];
}
