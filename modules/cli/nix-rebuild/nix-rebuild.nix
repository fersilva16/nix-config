# nix-rebuild [HOST]: switch any machine to ~/nix-config from any other one.
#   vega     darwin-rebuild on vega; from elsewhere, over ssh.
#   polaris  nixos-rebuild on polaris; from elsewhere, over ssh.
#   altair   built on polaris and pushed with --target-host. When polaris is
#            down, it alarms and offers to build on altair itself.
# The host that builds pulls main first, when main is checked out clean.
#
# System-wide, so another machine's ssh finds it at a fixed path.
{
  mkUserModule,
  config,
  pkgs,
  ...
}:
let
  nix-rebuild = pkgs.writeShellApplication {
    name = "nix-rebuild";
    text = ''
      here=${config.networking.hostName}
    ''
    + builtins.readFile ./nix-rebuild.sh;
  };
in
mkUserModule {
  name = "nix-rebuild";
  system.environment.systemPackages = [ nix-rebuild ];
}
