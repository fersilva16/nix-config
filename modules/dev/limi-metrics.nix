# limi-metrics: the node exporter scraped into VictoriaMetrics, with the fleet
# page in front (linux only). Limi owns the services, ports and retention.
# This wrapper connects them to nix-config's user modules and fleet.
{
  mkUserModule,
  forPlatform,
  lib,
  ...
}:
mkUserModule {
  name = "limi-metrics";
  system =
    { enabledUsers }:
    forPlatform {
      darwin = { };
      linux = {
        services.limi-metrics = {
          enable = true;
          # The fleet page comes from this user's Limi profile.
          user = lib.head (lib.attrNames enabledUsers);
        };

        # The other hosts reach :8428 and :80 here (servicePorts).
        fleet.services = [ "metrics" ];
      };
    };
}
