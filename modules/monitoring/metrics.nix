# Metrics — node_exporter scraped into VictoriaMetrics (linux only).
#
# node_exporter listens on loopback only; VictoriaMetrics scrapes it every 15s
# and keeps a year of history. VictoriaMetrics has no login, so :8428 opens
# only on tailscale0: clients read it with PromQL at http://<host>:8428, and
# custom metrics are pushed to /api/v1/import/prometheus on the same port.
{
  mkUserModule,
  forPlatform,
  config,
  ...
}:
let
  port = 8428;
  nodePort = 9100;
in
mkUserModule {
  name = "metrics";
  system = forPlatform {
    linux = {
      fleet.services = [ "metrics" ];

      services.prometheus.exporters.node = {
        enable = true;
        listenAddress = "127.0.0.1";
        port = nodePort;
        enabledCollectors = [ "systemd" ];
      };

      services.victoriametrics = {
        enable = true;
        listenAddress = ":${toString port}";
        retentionPeriod = "1y";
        prometheusConfig = {
          global.scrape_interval = "15s";
          scrape_configs = [
            {
              job_name = "node";
              static_configs = [
                {
                  targets = [ "127.0.0.1:${toString nodePort}" ];
                  labels.instance = config.networking.hostName;
                }
              ];
            }
          ];
        };
      };

      networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ port ];
    };
  };
}
