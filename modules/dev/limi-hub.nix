# limi-hub: Limi's always-on daemon, for altair. Limi owns the service,
# account, state and secret wiring. This wrapper connects it to nix-config's
# user modules, fleet, backup and Home Manager activation.
{
  mkUserModule,
  config,
  forPlatform,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  host = inputs.limi.lib.host;
  # Every directory from $HOME down to the profile, which limi-hub must be
  # able to search to reach its binary.
  profileDirs =
    let
      parts = lib.splitString "/" (dirOf host.profile);
    in
    lib.genList (i: "$HOME/${lib.concatStringsSep "/" (lib.take (i + 1) parts)}") (lib.length parts);
in
mkUserModule {
  name = "limi-hub";
  requires = [ "tailscale" ];
  system =
    { enabledUsers }:
    forPlatform {
      darwin = { };
      linux =
        let
          user = lib.head (lib.attrNames enabledUsers);
          hub = config.services."limi-hub";
        in
        {
          services.limi-hub = {
            enable = true;
            inherit user;
          };

          # limi-suite's limi-host finds the hub here (fleetPeers).
          fleet.services = [ "limi-hub" ];

          # The hub's state exists nowhere else, so a host that backs up takes
          # it too, and the hub's user hears when the backup goes stale.
          modules.system.backup = {
            subvolumes = [ hub.home ];
            exclude = [ hub.mirror ];
            notify = lib.mkDefault user;
          };
        };
    };
  home.home = {
    packages = [ pkgs.tmux ];
    # limi-hub reaches its binary through these dirs, and a shell may have
    # made ~/.local 0700. `limi switch --host` fills the profile; until it
    # does, say how.
    activation.limiHubProfile = {
      after = [ "writeBoundary" ];
      before = [ ];
      data = ''
        run mkdir -p "${lib.last profileDirs}"
        run chmod o+x ${lib.concatStringsSep " " (map (d: ''"${d}"'') profileDirs)}
        if [ ! -x "$HOME/${host.profile}/${host.hub}" ]; then
          warnEcho "No limi-hub in ~/${host.profile}: the hub waits for it."
          warnEcho "Fill it from polaris with 'limi switch --host ${config.networking.hostName}'."
        fi
      '';
    };
  };
}
