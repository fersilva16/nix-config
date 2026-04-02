# user-bootstrap — automatically bootstraps user accounts and home-manager
# homes for every key in modules.users.
#
# When modules.users.fernando exists, this module sets:
#   - users.users.fernando.home (inferred from platform)
#   - home-manager.users.fernando.home.{username, homeDirectory, stateVersion}
#
# No explicit enable flag needed — existence of the user key is enough.
{
  config,
  lib,
  forPlatform,
  ...
}:
let
  allUsers = config.modules.users;
in
{
  options.modules.users = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        options.stateVersion = lib.mkOption {
          type = lib.types.str;
          default = "25.05";
          description = "home-manager state version for this user.";
        };
      }
    );
  };

  config = lib.mkIf (allUsers != { }) {
    users.users = lib.mapAttrs (username: _: {
      home = forPlatform {
        darwin = "/Users/${username}";
        linux = "/home/${username}";
      };
    }) allUsers;

    home-manager.users = lib.mapAttrs (username: userCfg: {
      home = {
        inherit username;
        homeDirectory = forPlatform {
          darwin = "/Users/${username}";
          linux = "/home/${username}";
        };
        inherit (userCfg) stateVersion;
      };
    }) allUsers;
  };
}
