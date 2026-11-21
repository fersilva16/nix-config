# Limi: everything it ships, as one package (limi-suite). Limi owns the suite
# and how a host wires it: `inputs.limi.homeModules.limi-suite` per user
# (limi-host, Nalum's home, the launcher, the mux's host side) and
# `inputs.limi.nixosModules.limi-suite` on NixOS (nix-ld, the profile on PATH,
# limi-host's port). This module only states what nix-config knows: the
# fleet, the user's peers and Slack workspace, whether niri runs.
#
# Limi owns the agent (Nalum is the host's omo, add-ons included), tmux
# (limi-desktop's mux), the wt/wts family, `lin` and the Slack Later tools;
# nix-config has no copies of them.
{
  mkUserModule,
  forPlatform,
  lib,
  fleetPeers,
  inputs,
  ...
}:
let
  # The fleet peer that runs limi-hub, if any.
  hub = lib.findFirst (name: lib.elem "limi-hub" fleetPeers.${name}.services) null (
    lib.attrNames fleetPeers
  );
in
mkUserModule {
  name = "limi-suite";
  requires = [ "omo-home" ];
  extraOptions.slackLater = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    default = { };
    example.workspace = "example.slack.com";
    description = "Limi's `programs.limi-suite.slackLater` for this user: `workspace`, `groupBy`.";
  };
  extraOptions.peers = lib.mkOption {
    type = lib.types.attrsOf (lib.types.listOf lib.types.str);
    default = { };
    example = {
      polaris = [
        "-D"
        "1080"
      ];
    };
    description = ''
      Extra ssh arguments per machine limi-desktop, its session picker and
      `limi attach` can reach. Fleet peers that advertise "ssh"
      (modules/system/fleet.nix) are always listed; an entry here adds args
      or a machine outside the fleet.
    '';
  };
  system = {
    fleet.services = [ "limi-host" ];
  }
  // forPlatform {
    linux.programs.limi-suite.enable = true;
  };
  home =
    { cfg, userCfg, ... }:
    {
      imports = [ inputs.limi.homeModules.limi-suite ];
      programs.limi-suite = {
        enable = true;
        inherit hub;
        inherit (cfg) slackLater;
        machines =
          lib.mapAttrs (_: _: [ ]) (lib.filterAttrs (_: peer: lib.elem "ssh" peer.services) fleetPeers)
          // cfg.peers;
        # `or false`: the niri option only exists on linux hosts.
        niri = userCfg.niri.enable or false;
      };
    };
}
