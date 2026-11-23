# limi-hub: Limi's always-on daemon, for altair. Limi's limi-hub module owns
# the service, its account, state and secrets, the user nalum it runs the
# personal Nalum as, and the hub user's Home Manager side. This module only
# names the user and ties the hub to nix-config's fleet and backup.
{
  mkUserModule,
  config,
  forPlatform,
  lib,
  ...
}:
mkUserModule {
  name = "limi-hub";
  requires = [ "tailscale" ];
  system =
    { enabledUsers }:
    forPlatform {
      darwin = { };
      linux =
        let
          user = lib.head (lib.attrNames enabledUsers);
          hub = config.services."limi-hub";
        in
        {
          services.limi-hub = {
            enable = true;
            inherit user;
          };

          # limi-suite's limi-host finds the hub here (fleetPeers).
          fleet.services = [ "limi-hub" ];

          # The hub's state exists nowhere else, so a host that backs up takes
          # it too, and the hub's user hears when the backup goes stale.
          modules.system.backup = {
            subvolumes = [ hub.home ];
            exclude = [ hub.mirror ];
            notify = lib.mkDefault user;
          };
        };
    };
}
