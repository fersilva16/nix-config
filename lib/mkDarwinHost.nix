# mkDarwinHost — creates a nix-darwin system from a structured declaration.
#
# Absorbs all darwin system plumbing (module discovery, specialArgs,
# home-manager/nix-homebrew wiring, nixpkgs config) so host files stay
# declarative. Mirrors the mkUser pattern: host files call the factory
# with an attrset, not raw module config.
#
# Designed for multi-platform: field names are platform-agnostic so a
# future mkNixOSHost can expose the same interface.
#
# Signature: { inputs } -> { hostName, primaryUser, ... } -> darwinSystem
#
# Fields:
#
#   hostName:     (required) Network hostname. Sets networking.hostName.
#
#   primaryUser:  (required) The primary user of this host. Accepts a user
#                 function (imported mkUser file) or a plain string.
#                 When a user function is provided, the username is extracted
#                 automatically from mkUser's { name, module } return value.
#
#   system:       (optional, default "aarch64-darwin") Nix system identifier.
#
#   stateVersion: (optional, default 5) nix-darwin state version.
#
#   users:        (optional, default []) List of user functions (imported
#                 mkUser files). Each is called with specialArgs during module
#                 evaluation; mkDarwinHost unwraps the { name, module } return
#                 to feed .module to the module system.
#
#   extraModules: (optional, default []) Escape hatch for additional modules
#                 not covered by the standard fields.
#
# Usage:
#
#   # modules/hosts/m1.nix
#   { mkDarwinHost }:
#   let
#     fernando = import ../users/m1-fernando.nix;
#   in
#   mkDarwinHost {
#     hostName = "m1";
#     primaryUser = fernando;
#     users = [ fernando ];
#   }
#
#   # flake.nix
#   m1 = import ./modules/hosts/m1.nix { inherit mkDarwinHost; };
#
{ inputs }:
let
  inherit (inputs)
    darwin
    home-manager
    nix-homebrew
    nixpkgs
    ;

  mkUser = import ./mkUser.nix;

  discoverModules = import ./discoverModules.nix { inherit (nixpkgs) lib; };

  globalModules = discoverModules {
    modulesDir = ../modules;
  };

  # Resolve a user reference to its username string.
  # Accepts a user function (imported mkUser file) or a plain string.
  resolveUserName =
    user:
    if builtins.isString user then
      user
    else
      # Call the user function with mkUser to get { name, module }
      (user { inherit mkUser; }).name;

  # Wrap a user function so the module system receives the inner module.
  # The user function returns { name, module } via mkUser — we unwrap .module.
  userToModule = userFn: args: (userFn args).module;
in
{
  hostName,
  primaryUser,
  system ? "aarch64-darwin",
  stateVersion ? 5,
  users ? [ ],
  extraModules ? [ ],
}:
darwin.lib.darwinSystem {
  inherit system;

  specialArgs = {
    inherit inputs system;
    mkUserModule = import ./mkUserModule.nix;
    mkSystemModule = import ./mkSystemModule.nix;
    inherit mkUser;
    forPlatform = import ./forPlatform.nix system;
  };

  modules = [
    home-manager.darwinModules.home-manager
    nix-homebrew.darwinModules.nix-homebrew

    {
      networking.hostName = hostName;
      system.primaryUser = resolveUserName primaryUser;
      system.stateVersion = stateVersion;

      nixpkgs = {
        config.allowUnfree = true;
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
