# Metrics — node_exporter scraped into VictoriaMetrics (linux only).
#
# node_exporter listens on loopback only; VictoriaMetrics scrapes it every 15s
# and keeps a year of history. VictoriaMetrics has no login, so :8428 opens
# only on tailscale0: clients read it with PromQL at http://<host>:8428, and
# custom metrics are pushed to /api/v1/import/prometheus on the same port.
#
# nginx serves Limi's fleet page on :80, also tailnet-only, and passes it only
# the two read paths of VictoriaMetrics, so the page cannot write metrics.
{
  mkUserModule,
  forPlatform,
  config,
  inputs,
  lib,
  ...
}:
let
  host = inputs.limi.lib.host;
  port = 8428;
  nodePort = 9100;
  webPort = 80;
  metricsApi = {
    proxyPass = "http://127.0.0.1:${toString port}";
  };
in
mkUserModule {
  name = "metrics";
  system =
    { enabledUsers }:
    let
      # The fleet page comes from this user's Limi profile.
      user = lib.head (lib.attrNames enabledUsers);
      profiles = "/home/${user}/${dirOf host.profile}";
    in
    forPlatform {
      linux = {
        fleet.services = [ "metrics" ];

        services = {
          prometheus.exporters.node = {
            enable = true;
            listenAddress = "127.0.0.1";
            port = nodePort;
            enabledCollectors = [ "systemd" ];
          };

          victoriametrics = {
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

          nginx = {
            enable = true;
            virtualHosts.fleet = {
              default = true;
              # Limi's fleet package, in the profile `limi switch` fills. Until
              # it holds the page, nginx answers 404.
              root = "${profiles}/${baseNameOf host.profile}/share/fleet";
              locations."= /api/v1/query" = metricsApi;
              locations."= /api/v1/query_range" = metricsApi;
            };
          };
        };

        # nginx sees no /home (ProtectHome). Show it only the profiles dir,
        # read-only, once Home Manager has made it; a profile switch inside it
        # reaches nginx with no restart.
        systemd.services.nginx = {
          after = [ "home-manager-${user}.service" ];
          serviceConfig = {
            ProtectHome = lib.mkForce "tmpfs";
            BindReadOnlyPaths = [ "-${profiles}" ];
          };
        };

        networking.firewall.interfaces.tailscale0.allowedTCPPorts = [
          port
          webPort
        ];
      };
    };
}
