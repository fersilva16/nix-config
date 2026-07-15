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
#   stateVersion: (optional, default "26.05") home-manager state version.
#
#   <anything else>: Passed directly to `modules.users.<name>`.
#                    Typically module enable flags and their options.
#
# Usage:
#
#   # modules/users/vega-fernando.nix — user file (unchanged):
#   { mkUser, ... }:
#   mkUser {
#     name = "fernando";
#     bat.enable = true;
#     git.enable = true;
#   }
#
#   # modules/hosts/vega.nix — host file uses the { name, module } shape:
#   { mkDarwinHost }:
#   let
#     fernando = import ../users/vega-fernando.nix;
#   in
#   mkDarwinHost {
#     hostName = "vega";
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
  stateVersion ? "26.05",
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

          users.users.${name} = {
            home = forPlatform {
              darwin = "/Users/${name}";
              linux = "/home/${name}";
            };
          }
          # NixOS requires an explicit account class (darwin does not) and
          # won't create the account without it.
          // forPlatform {
            linux = {
              isNormalUser = true;
              extraGroups = [
                "wheel"
                "networkmanager"
              ];
            };
          };

          home-manager.users.${name} = {
            home = {
              username = name;
              homeDirectory = forPlatform {
                darwin = "/Users/${name}";
                linux = "/home/${name}";
              };
              inherit stateVersion;
            };

            # On darwin with stateVersion >= 26.05, programs.man.package
            # defaults to null (macOS provides its own man). Disable cache
            # generation explicitly so HM doesn't warn about a no-op.
            programs.man.generateCaches = false;
          };
        }
      )
    ];
  };
}
