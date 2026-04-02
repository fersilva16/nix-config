{ mkDarwinHost }:
let
  fernando = import ../users/m1-fernando.nix;
in
mkDarwinHost {
  hostName = "m1";
  primaryUser = fernando;
  users = [ fernando ];
}
