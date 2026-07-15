{ mkDarwinHost }:
let
  fernando = import ../users/vega-fernando.nix;
in
mkDarwinHost {
  hostName = "vega";
  primaryUser = fernando;
  users = [ fernando ];
}
