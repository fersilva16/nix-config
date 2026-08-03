{ mkSystemModule, pkgs, ... }:
mkSystemModule {
  name = "nix";
  config.nix = {
    package = pkgs.nixVersions.latest;

    extraOptions = ''
      experimental-features = nix-command flakes
    '';

    # Self-limiting store. The daemon defaults to min-free = 0, meaning a
    # build will happily fill the disk to zero. Below 25G free it collects
    # garbage mid-build until 100G is free again.
    settings = {
      min-free = 25 * 1024 * 1024 * 1024;
      max-free = 100 * 1024 * 1024 * 1024;
    };

    # Hard-link identical files in the store. Reclaims space without
    # removing anything, so nothing is ever re-downloaded.
    optimise.automatic = true;

    # Keep 30 days of rollbacks. nix-direnv pins dev shells via GC roots,
    # so this only drops stale generations, not anything in active use.
    gc = {
      automatic = true;
      options = "--delete-older-than 30d";
    };
  };
}
