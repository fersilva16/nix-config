# AdGuard Home — network-wide DNS with ad/tracker blocking (linux only).
#
# DNS on :53 for the LAN and the tailnet; the web UI on :3000. Point the
# router's DHCP DNS at this host (give it a DHCP reservation first) to cover
# the whole home network.
#
# mutableSettings: what is declared here is re-applied on every start, while
# anything changed in the web UI (clients, extra lists) survives.
{ mkUserModule, forPlatform, ... }:
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
          };
          filtering = {
            protection_enabled = true;
            filtering_enabled = true;
          };
          filters = [
            {
              enabled = true;
              id = 1;
              name = "AdGuard DNS filter";
              url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt";
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
