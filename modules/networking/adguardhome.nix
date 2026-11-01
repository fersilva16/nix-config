# AdGuard Home — network-wide DNS with ad/tracker blocking (linux only).
#
# DNS on :53 for the LAN and the tailnet; the web UI on :3000. Point the
# router's DHCP DNS at this host (give it a DHCP reservation first) to cover
# the whole home network.
#
# mutableSettings: what is declared here is re-applied on every start, while
# anything changed in the web UI (clients, extra lists) survives.
{
  mkUserModule,
  forPlatform,
  lib,
  ...
}:
mkUserModule {
  name = "adguardhome";
  system = forPlatform {
    linux = {
      fleet.services = [ "dns" ];

      services.adguardhome = {
        enable = true;
        mutableSettings = true;
        # Opens the web UI port (:3000).
        openFirewall = true;
        settings = {
          dns = {
            bind_hosts = [ "0.0.0.0" ];
            port = 53;
            upstream_dns = [
              "https://dns.quad9.net/dns-query"
              "https://cloudflare-dns.com/dns-query"
            ];
            bootstrap_dns = [
              "9.9.9.9"
              "1.1.1.1"
            ];
            # DoH upstreams cost ~10 ms more than the router's plain DNS on a
            # first lookup: race both upstreams and answer expired entries from
            # cache while refreshing them in the background.
            upstream_mode = "parallel";
            cache_optimistic = true;
            cache_size = 16 * 1024 * 1024;
          };
          filtering = {
            protection_enabled = true;
            filtering_enabled = true;
          };
          filters =
            lib.imap1
              (id: f: {
                inherit id;
                enabled = true;
                inherit (f) name;
                url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_${toString f.registry}.txt";
              })
              [
                {
                  name = "AdGuard DNS filter";
                  registry = 1;
                }
                {
                  name = "HaGeZi's Pro Blocklist";
                  registry = 48;
                }
                {
                  name = "HaGeZi's Threat Intelligence Feeds";
                  registry = 44;
                }
                {
                  name = "HaGeZi's Windows/Office Tracker Blocklist";
                  registry = 63;
                }
                {
                  name = "HaGeZi's Samsung Tracker Blocklist";
                  registry = 61;
                }
                {
                  name = "HaGeZi's LG webOS Tracker Blocklist";
                  registry = 72;
                }
              ];
        };
      };

      networking.firewall = {
        allowedTCPPorts = [ 53 ];
        allowedUDPPorts = [ 53 ];
      };
    };
  };
}
