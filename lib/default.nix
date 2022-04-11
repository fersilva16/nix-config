{ inputs, overlays ? [ ] }:
let
  inherit (inputs) nixpkgs home-manager;
in
{
  makeHost = { hostname, system ? "x86_64-linux", users ? [ ] }:
    nixpkgs.lib.nixosSystem {
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
      ] ++ nixpkgs.lib.forEach users (user: ../users/${user});
    };

  makeHome = { username, system ? "x86_64-linux", hostname }:
    home-manager.lib.homeManagerConfiguration {
      inherit username system;

      extraSpecialArgs = {
        inherit inputs system hostname;
      };

      homeDirectory = "/home/${username}";
      configuration = ../homes/${username};

      extraModules = [
        {
          nixpkgs = {
            inherit overlays;
            config.allowUnfree = true;
          };

          programs = {
            home-manager.enable = true;
            git.enable = true;
          };
        }
      ];
    };
}
