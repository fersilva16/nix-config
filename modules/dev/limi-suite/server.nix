# limi-server serves the mux and Nalum's sessions; `limi-server keep` keeps
# the home server up with no window open, so the phone reaches it on port
# 7377. `limi-server token` prints the bearer token.
{
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
      server = "${profile}/${host.path}/limi-server";
    in
    forPlatform {
      linux.systemd.user.services.limi-server = {
        Unit.Description = "limi-server keep: the home mux server and Nalum's API";
        Service = {
          ExecStart = "${server} keep";
          # keep starts the server, which must outlive a restart of keep.
          KillMode = "process";
          Environment = [ "PATH=${profile}/${host.path}:${profile}/bin:/run/current-system/sw/bin" ];
          Restart = "always";
          RestartSec = 2;
        };
        Install.WantedBy = [ "default.target" ];
      };
      darwin.launchd.agents.limi-server = {
        enable = true;
        config = {
          ProgramArguments = [
            server
            "keep"
          ];
          RunAtLoad = true;
          KeepAlive = true;
          # keep starts the server, which must outlive a restart of keep.
          AbandonProcessGroup = true;
          # Every pane the server spawns inherits this; Background throttles
          # their CPU and I/O to macOS's lowest band.
          ProcessType = "Interactive";
          StandardErrorPath = "${homeOf username}/Library/Logs/limi-server-keep.log";
        };
      };
    };
}
