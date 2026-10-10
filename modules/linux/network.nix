# NetworkManager + redistributable firmware (WiFi/BT chips need it —
# polaris: Realtek RTL8922AE).
{ mkSystemModule, ... }:
mkSystemModule {
  name = "network";
  config = {
    networking.networkmanager.enable = true;
    hardware.enableRedistributableFirmware = true;

    # Publish <host>.local over mDNS so LAN peers can reach this machine
    # directly (ssh.nix prefers polaris.local over the tailnet when it
    # answers). nssmdns4 lets this host resolve .local names too.
    services.avahi = {
      enable = true;
      nssmdns4 = true;
      publish = {
        enable = true;
        addresses = true;
      };
    };

    # BBR paces by measured bandwidth/RTT instead of backing off on every
    # lost packet, so long-RTT downloads over jittery WiFi (polaris ->
    # cache.nixos-cuda.org in Finland, ~270 ms) keep their rate. fq is the
    # qdisc BBR is designed to pair with.
    boot.kernelModules = [ "tcp_bbr" ];
    boot.kernel.sysctl = {
      "net.ipv4.tcp_congestion_control" = "bbr";
      "net.core.default_qdisc" = "fq";
    };
  };
}
