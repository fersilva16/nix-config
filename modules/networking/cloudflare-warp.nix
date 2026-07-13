{ mkUserModule, ... }:
mkUserModule {
  name = "cloudflare-warp";
  casks = [ "cloudflare-warp" ];
}
