# mkNixOSHost — creates a NixOS system from a structured declaration.
#
# Mirror of mkDarwinHost with the same platform-agnostic interface, so host
# files stay declarative regardless of platform. Differences from darwin:
#   - nixpkgs.lib.nixosSystem instead of darwin.lib.darwinSystem
#   - home-manager.nixosModules instead of darwinModules
#   - no nix-homebrew (Homebrew is a darwin concept)
#   - module discovery excludes modules/darwin/ instead of modules/linux/
#
# Signature: { inputs } -> { hostName, primaryUser, ... } -> nixosSystem
#
# Fields (identical shape to mkDarwinHost):
#
#   hostName:     (required) Network hostname. Sets networking.hostName.
#
#   primaryUser:  (required) The primary user of this host. Accepts a user
#                 function (imported mkUser file) or a plain string.
#                 Currently informational on NixOS (darwin needs it for
#                 system.primaryUser; kept for interface parity).
#
#   system:       (optional, default "x86_64-linux") Nix system identifier.
#
#   stateVersion: (optional, default "26.05") NixOS state version (string,
#                 unlike nix-darwin's integer).
#
#   users:        (optional, default []) List of user functions (imported
#                 mkUser files).
#
#   extraModules: (optional, default []) Escape hatch for additional modules
#                 (hardware config, disko layout, ...).
#
# Usage:
#
#   # modules/hosts/polaris.nix
#   { mkNixOSHost }:
#   let
#     fernando = import ../users/polaris-fernando.nix;
#   in
#   mkNixOSHost {
#     hostName = "polaris";
#     primaryUser = fernando;
#     users = [ fernando ];
#   }
#
{ inputs }:
let
  inherit (inputs) home-manager;
  # NixOS hosts evaluate against nixos-unstable (see flake.nix inputs).
  nixpkgs = inputs.nixpkgs-nixos;

  mkUser = import ./mkUser.nix;

  discoverModules = import ./discoverModules.nix { inherit (nixpkgs) lib; };

  globalModules = discoverModules {
    modulesDir = ../modules;
    exclude = [
      "hosts"
      "users"
      "darwin"
    ];
  };

  # Wrap a user function so the module system receives the inner module.
  userToModule = userFn: args: (userFn args).module;
in
{
  hostName,
  # Unused on NixOS for now (darwin needs system.primaryUser); accepted for
  # interface parity with mkDarwinHost.
  primaryUser,
  system ? "x86_64-linux",
  stateVersion ? "26.05",
  users ? [ ],
  extraModules ? [ ],
}:
nixpkgs.lib.nixosSystem {
  inherit system;

  specialArgs = {
    inherit inputs system;
    mkUserModule = import ./mkUserModule.nix;
    mkSystemModule = import ./mkSystemModule.nix;
    inherit mkUser;
    forPlatform = import ./forPlatform.nix system;
  };

  modules = [
    home-manager.nixosModules.home-manager

    {
      networking.hostName = hostName;
      system.stateVersion = stateVersion;

      nixpkgs = {
        config.allowUnfree = true;
        # Same overlay as mkDarwinHost — vscode module references
        # pkgs.vscode-marketplace on every platform.
        overlays = [ inputs.nix-vscode-extensions.overlays.default ];
      };

      home-manager = {
        useGlobalPkgs = true;
      };
    }
  ]
  ++ map userToModule users
  ++ extraModules
  ++ globalModules;
}
