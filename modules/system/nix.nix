{ mkSystemModule, pkgs, ... }:
mkSystemModule {
  name = "nix";
  config.nix = {
    package = pkgs.nixVersions.latest;

    extraOptions = ''
      experimental-features = nix-command flakes
    '';

    # crates.io's Fastly edge 403s any User-Agent containing "curl/", which
    # is exactly what nixpkgs' fetchurl sends ("curl/$ver Nixpkgs/$ver"), so
    # every Rust build that vendors from crates.io fails to fetch. Verified
    # against the same URL at the same moment: UA "curl/8.7.1" -> 403,
    # UA "nix" -> 302. The fetchurl builder appends $NIX_CURL_FLAGS after
    # its own --user-agent and curl honours the last one, so this overrides
    # it. It has to live here rather than in the calling shell: NIX_CURL_FLAGS
    # is an impureEnvVar, and on a multi-user install those are read from the
    # daemon's environment, not the client's.
    envVars.NIX_CURL_FLAGS = "--user-agent nix";

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
