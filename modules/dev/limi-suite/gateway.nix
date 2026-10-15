# nalum-gateway (Limi's js/services/nalum-gateway) serves the running Nalum
# sessions over HTTP to devices on the home network, behind a bearer token
# (`nalum-gateway token` prints it). It runs from the limi profile, so a
# `limi switch` reaches it on the next `systemctl --user restart
# nalum-gateway`. Linux only for now: polaris runs the sessions it serves.
{
  pkgs,
  host,
  homeOf,
  forPlatform,
}:
let
  port = 7377;
in
{
  system = forPlatform {
    linux.networking.firewall.allowedTCPPorts = [ port ];
  };
  home =
    { username, ... }:
    let
      profile = "${homeOf username}/${host.profile}";
    in
    forPlatform {
      linux.systemd.user.services.nalum-gateway = {
        Unit.Description = "nalum-gateway: Nalum's coding sessions over the home network";
        Service = {
          ExecStart = "${profile}/bin/nalum-gateway";
          # tmux must match the user's server; omo and agent are the ones the
          # suite installs (bin/omo would sync ~/.omo on every call).
          Environment = [
            "PATH=${profile}/bin:${pkgs.tmux}/bin:/run/current-system/sw/bin"
            "NALUM_GATEWAY_OMO=${profile}/libexec/omo"
            "NALUM_GATEWAY_AGENT=${profile}/bin/agent"
            "NALUM_GATEWAY_PORT=${toString port}"
          ];
          Restart = "on-failure";
          RestartSec = 5;
        };
        Install.WantedBy = [ "default.target" ];
      };
    };
}
