# NetworkManager + redistributable firmware (WiFi/BT chips need it —
# polaris: Realtek RTL8922AE).
{ mkSystemModule, ... }:
mkSystemModule {
  name = "network";
  config = {
    networking.networkmanager.enable = true;
    hardware.enableRedistributableFirmware = true;

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
