{
  mkSystemModule,
  forPlatform,
  pkgs,
  ...
}:
let
  accessTokensFile = "/etc/nix/access-tokens.conf";
  # Place the Nix vault's service account token here by hand once per machine.
  # opnix keeps it root:onepassword-secrets 0640 and adds fernando to the group.
  opnixTokenFile = forPlatform {
    darwin = "/usr/local/etc/opnix-nix-token";
    linux = "/etc/opnix-nix-token";
  };
in
mkSystemModule {
  name = "nix";
  config = {
    services.onepassword-secrets = {
      enable = true;
      tokenFile = opnixTokenFile;
      users = [ "fernando" ];
      secrets.nixAccessTokens = {
        reference = "op://Nix/Nix Access Tokens/password";
        path = accessTokensFile;
        owner = "fernando";
        group = "wheel";
        mode = "0600";
      };
    };

    nix = {
      package = pkgs.nixVersions.latest;

      extraOptions = ''
        experimental-features = nix-command flakes
        # The first rebuild has no generated file yet. `!include` ignores it,
        # then every later evaluation can fetch private GitHub flake inputs.
        !include ${accessTokensFile}
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
  // forPlatform {
    # The timer is Persistent, so a run missed while powered off fires right
    # at boot — 2+ GB of store I/O racing the login session. Idle scheduling
    # lets it yield to anything else wanting CPU or disk.
    linux.systemd.services.nix-gc.serviceConfig = {
      CPUSchedulingPolicy = "idle";
      IOSchedulingClass = "idle";
    };
  };
}
