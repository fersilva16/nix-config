{ mkSystemModule, lib, ... }:
mkSystemModule {
  name = "spotlight";
  extraOptions.indexing = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Whether Spotlight indexes volumes (mds/mds_stores).";
  };
  config =
    { cfg, ... }:
    {
      # ponytail: no declarative nix-darwin option exists; mdutil is idempotent.
      system.activationScripts.postActivation.text = ''
        mdutil -a -i ${if cfg.indexing then "on" else "off"} >/dev/null
      '';
    };
}
