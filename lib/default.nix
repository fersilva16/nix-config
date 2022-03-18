{ inputs, overlays ? [] }:
let
  inherit (inputs.nixpkgs) lib;
in
{
  makeHost = { hostname, system ? "x86_64-linux", users ? [] }:
    lib.nixosSystem {
      inherit system;

      specialArgs = {
        inherit inputs system hostname;
      };

      modules = [
        ../hosts/${hostname}
        {
          networking.hostName = hostname;
          nixpkgs = {
            inherit overlays;
            config.allowUnfree = true;
          };
        }
      ] ++ lib.forEach users (user: ../users/${user});
    };
}
