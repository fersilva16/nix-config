# mkUser — creates a user module that bootstraps the system account,
# home-manager home, and module enable flags in one declaration.
#
# Absorbs the bootstrapping that user-bootstrap.nix used to handle
# (home directory, username, stateVersion) so user files stay declarative
# and don't leak raw config paths.
#
# Signature: { name, stateVersion? } // moduleEnables -> module
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
#   # Simple — just enable flags:
#   { mkUser, ... }:
#   mkUser {
#     name = "fernando";
#     bat.enable = true;
#     git.enable = true;
#     fish.enable = true;
#   }
#
#   # With module options and part toggles:
#   { mkUser, ... }:
#   mkUser {
#     name = "fernando";
#     stateVersion = "25.11";
#     bat.enable = true;
#     opencode = { enable = true; server.enable = false; };
#     nvim = { enable = true; ai.enable = false; };
#   }
#
# What it does:
#
#   1. Sets modules.users.<name> with all module enables/options.
#   2. Creates users.users.<name>.home (platform-aware via forPlatform).
#   3. Creates home-manager.users.<name>.home with username, homeDirectory,
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
}
