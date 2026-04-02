# mkUser — creates a user module that bootstraps the system account,
# home-manager home, and module enable flags in one declaration.
#
# Returns { name, module } so host factories (mkDarwinHost, mkNixOSHost)
# can extract the username for primaryUser without duplication.
#
# Signature: { name, stateVersion? } // moduleEnables -> { name, module }
#
# Fields:
#
#   name:         Username. Creates the system account, home-manager home,
#                 and sets `modules.users.<name>` with the remaining attrs.
#
#   stateVersion: (optional, default "25.11") home-manager state version.
#
#   <anything else>: Passed directly to `modules.users.<name>`.
#                    Typically module enable flags and their options.
#
# Usage:
#
#   # modules/users/m1-fernando.nix — user file (unchanged):
#   { mkUser, ... }:
#   mkUser {
#     name = "fernando";
#     bat.enable = true;
#     git.enable = true;
#   }
#
#   # modules/hosts/m1.nix — host file uses the { name, module } shape:
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
# What it does:
#
#   1. Returns { name, module } where:
#      - name: the username string (for host factories to read)
#      - module: a NixOS/darwin module that sets up the user
#   2. The module sets modules.users.<name> with all module enables/options.
#   3. Creates users.users.<name>.home (platform-aware via forPlatform).
#   4. Creates home-manager.users.<name>.home with username, homeDirectory,
#      and stateVersion.
#
{
  name,
  stateVersion ? "25.11",
  ...
}@args:
let
  moduleEnables = builtins.removeAttrs args [
    "name"
    "stateVersion"
  ];
in
{
  inherit name;
  module = {
    imports = [
      (
        { forPlatform, ... }:
        {
          modules.users.${name} = moduleEnables;

          users.users.${name}.home = forPlatform {
            darwin = "/Users/${name}";
            linux = "/home/${name}";
          };

          home-manager.users.${name}.home = {
            username = name;
            homeDirectory = forPlatform {
              darwin = "/Users/${name}";
              linux = "/home/${name}";
            };
            inherit stateVersion;
          };
        }
      )
    ];
  };
}
