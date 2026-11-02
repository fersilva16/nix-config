# limi-host serves the mux and Nalum's sessions; `limi-host keep` keeps the
# main mux up with no window open, so the phone reaches it on port 7377.
# `limi-host token` prints the bearer token.
#
# limi-host reaches limi-hub (modules/dev/limi-hub.nix) with the hub's token
# in ~/.local/state/limi/hub-token (0600), placed by hand: nothing secret
# enters the store.
{
  host,
  homeOf,
  forPlatform,
  fleetPeers,
  lib,
  pkgs,
}:
let
  port = 7377;
  # The fleet peer that runs limi-hub, if any.
  hub = lib.findFirst (name: lib.elem "limi-hub" fleetPeers.${name}.services) null (
    lib.attrNames fleetPeers
  );
  # Loopback end of the tunnel below.
  tunnelPort = 17377;
in
{
  system = forPlatform {
    linux.networking.firewall.allowedTCPPorts = [ port ];
  };
  home =
    { username, userCfg, ... }:
    let
      profile = "${homeOf username}/${host.profile}";
      server = "${profile}/${host.path}/limi-host";
      # A userspace tailscaled adds no route or resolver for the tailnet, so
      # limi-host's default http://<hub>:7377 resolves nowhere. launchd hands
      # each connection to a loopback port to `tailscale nc` instead.
      tunnel =
        hub != null
        && pkgs.stdenv.hostPlatform.isDarwin
        && userCfg.tailscale.enable
        && userCfg.tailscale.userspace;
      hubEnv = lib.optionalAttrs tunnel { LIMI_HUB_URL = "http://127.0.0.1:${toString tunnelPort}"; };
    in
    lib.mkMerge [
      (forPlatform {
        linux.systemd.user.services.limi-host = {
          Unit.Description = "limi-host keep: the main mux and Nalum's API";
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
        darwin.launchd.agents.limi-host = {
          enable = true;
          config = {
            # macOS charges every pane's privacy request to keep, the process
            # that starts the server. The signed copy in Limi.app keeps its
            # grants across builds; the store binary is new to macOS each time.
            ProgramArguments = [
              "${homeOf username}/${host.macHost}"
              "keep"
            ];
            EnvironmentVariables = hubEnv;
            RunAtLoad = true;
            KeepAlive = true;
            # keep starts the server, which must outlive a restart of keep.
            AbandonProcessGroup = true;
            # Every pane the server spawns inherits this; Background throttles
            # their CPU and I/O to macOS's lowest band.
            ProcessType = "Interactive";
            StandardErrorPath = "${homeOf username}/Library/Logs/limi-host-keep.log";
          };
        };
      })
      (lib.mkIf (hub != null) {
        home.activation.limiHubToken = {
          after = [ "writeBoundary" ];
          before = [ ];
          data = ''
            if [ ! -s "$HOME/.local/state/limi/hub-token" ]; then
              warnEcho "No limi-hub token at ~/.local/state/limi/hub-token: limi-host has no calendar, mail or feeds."
              warnEcho "Get it on ${hub} with 'sudo -u limi-hub -H limi-hub token' and save it there, mode 0600."
            fi
          '';
        };
      })
      (lib.mkIf tunnel {
        # Shells too, so `limi-host` run by hand reaches the same hub.
        home.sessionVariables = hubEnv;
        # A daemon that Limi.app or a pane started has neither; Limi reads
        # the address from here when the variable is unset.
        xdg.configFile."limi/hub-url".text = hubEnv.LIMI_HUB_URL;
        launchd.agents.limi-hub-tunnel = {
          enable = true;
          config = {
            ProgramArguments = [
              "${pkgs.tailscale}/bin/tailscale"
              "nc"
              hub
              (toString port)
            ];
            inetdCompatibility.Wait = false;
            Sockets.Listeners = {
              SockNodeName = "127.0.0.1";
              SockServiceName = toString tunnelPort;
            };
          };
        };
      })
    ];
}
