# limi-hub (inputs.limi): Limi's always-on daemon, for altair. It serves the
# other machines' limi-host (limi-suite/server.nix) over the tailnet. Its
# one-time setup is manual and lives in Limi.
{
  mkUserModule,
  forPlatform,
  inputs,
  pkgs,
  lib,
  ...
}:
let
  limi = inputs.limi.packages.${pkgs.stdenv.hostPlatform.system};
  port = 7377;
in
mkUserModule {
  name = "limi-hub";
  # The hub's clients reach it over the tailnet only.
  requires = [ "tailscale" ];
  system =
    { enabledUsers }:
    let
      user = lib.head (lib.attrNames enabledUsers);
      home = "/home/${user}";
    in
    {
      # limi-suite's limi-host finds the hub here (fleetPeers).
      fleet.services = [ "limi-hub" ];
    }
    // forPlatform {
      linux = {
        assertions = [
          {
            assertion = lib.length (lib.attrNames enabledUsers) == 1;
            message = "limi-hub serves one user; enable it for exactly one.";
          }
        ];

        users = {
          users = {
            limi-hub = {
              isSystemUser = true;
              group = "limi-hub";
              extraGroups = [ "nalum" ];
              home = "/var/lib/limi-hub";
              createHome = true;
              homeMode = "700";
            };
            ${user}.homeMode = "711";
          };
          groups = {
            limi-hub = { };
            nalum.members = [
              user
              "limi-hub"
            ];
          };
        };

        systemd.tmpfiles.rules = [
          "z ${home}/nalum 2770 ${user} nalum -"
          "d ${home}/nalum/.agent 2770 ${user} nalum -"
          "Z ${home}/nalum/.agent - ${user} nalum -"
          "d ${home}/nalum/.agent/nalum 2770 ${user} nalum -"
          "d ${home}/.nalum 0710 ${user} nalum -"
          "d ${home}/.nalum/agent 0710 ${user} nalum -"
          "d ${home}/.nalum/agent/nalum 0710 ${user} nalum -"
          "d ${home}/.nalum/agent/nalum/bridge 2770 ${user} nalum -"
          "L+ ${home}/nalum/.agent/nalum/bridge - - - - ${home}/.nalum/agent/nalum/bridge"
        ];

        security.sudo.extraRules = [
          {
            users = [ "limi-hub" ];
            runAs = user;
            commands = [
              {
                command = "ALL";
                options = [
                  "NOPASSWD"
                  "SETENV"
                ];
              }
            ];
          }
        ];

        systemd.services.limi-hub = {
          wantedBy = [ "multi-user.target" ];
          after = [
            "network-online.target"
            "tailscaled.service"
          ];
          wants = [ "network-online.target" ];
          path = [ "/run/wrappers" ];
          environment = {
            LIMI_NALUM_PROJECTS = "${home}/nalum";
            OMO_CODING_AGENT_DIR = "${home}/nalum/.agent";
          };
          serviceConfig = {
            User = "limi-hub";
            Group = "limi-hub";
            ExecStart = "${limi.limi-hub}/bin/limi-hub";
            Restart = "always";
            UMask = "0077";
          };
        };

        # Tailnet only: never on the LAN interface.
        networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ port ];
      };
    };
  home.home.packages = forPlatform {
    linux = [
      limi.limi-hub-suite
      pkgs.tmux
    ];
  };
}
