# limi-metrics: the node exporter scraped into VictoriaMetrics, both on
# loopback (linux only). Limi owns the services, listen addresses and
# retention. This wrapper connects them to nix-config's user modules.
{
  mkUserModule,
  forPlatform,
  ...
}:
mkUserModule {
  name = "limi-metrics";
  system = forPlatform {
    darwin = { };
    linux.services.limi-metrics.enable = true;
  };
}
