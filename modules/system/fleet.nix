# What this machine advertises to the rest of the fleet
# (modules/hosts/fleet.nix). Every other host reads it as `fleetPeers.<thisHost>`,
# so modules set it from what they actually configure here: sshd adds "ssh",
# the ollama server adds "ollama", lan-mouse adds each user's certificate
# fingerprint.
#
# Must never depend on `fleetPeers`: the other hosts read this while they build,
# so a value that reads them back is an infinite recursion.
{ lib, ... }:
{
  options.fleet = lib.mkOption {
    type = lib.types.submodule {
      freeformType = lib.types.attrsOf lib.types.anything;
      options.services = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "What other machines can reach this one for, e.g. ssh, ollama.";
      };
    };
    default = { };
    description = "Facts this machine advertises to its fleet peers.";
  };
}
