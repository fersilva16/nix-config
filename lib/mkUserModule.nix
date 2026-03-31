# mkUserModule — creates a unified module that handles both system-level
# and per-user home-manager config, with multi-user support.
#
# Each module declares an enable option under `modules.users.<name>.<moduleName>`.
# When any user enables it, system config runs once; home config runs per-user.
#
# Signature: { name, system?, home?, user?, extraOptions?, requires? } -> module
#
# Fields:
#
#   name:         Module name. Creates `modules.users.<user>.<name>.enable` option.
#
#   system:       (optional) System-level config applied once when any user enables
#                 the module. Always a static attrset.
#
#   home:         (optional) Per-user home-manager config. Can be an attrset (static)
#                 or a function ({ cfg, username } -> attrset) when per-user option
#                 values are needed. Merged into home-manager.users.<username>.
#
#   user:         (optional) Per-user nix-darwin user account config. Can be an
#                 attrset (static) or a function ({ cfg, username } -> attrset).
#                 Merged into users.users.<username>. Use for per-user system-level
#                 settings like login shell.
#
#   extraOptions: (optional) Custom per-user option declarations (attrset of mkOption defs).
#
#   requires:     (optional) List of module names to auto-enable for every user
#                 who enables this module. The required modules must be imported
#                 in the system — this only sets `enable = true`, it does not
#                 configure their extraOptions (users set those, or defaults apply).
#
# User composition (in user file):
#
#   modules.users.fernando = {
#     bat.enable = true;
#     git = { enable = true; userName = "Fernando"; userEmail = "..."; };
#   };
#
{
  name,
  system ? { },
  home ? { },
  user ? { },
  extraOptions ? { },
  requires ? [ ],
}:
let
  isHomeFn = builtins.isFunction home;
  isUserFn = builtins.isFunction user;
  hasUser = user != { } || isUserFn;
in
{
  imports = [
    (
      { config, lib, ... }:
      let
        enabledUsers = lib.filterAttrs (_: u: u.${name}.enable) config.modules.users;
        hasEnabled = enabledUsers != { };
      in
      {
        options.modules.users = lib.mkOption {
          type = lib.types.attrsOf (
            lib.types.submodule {
              options.${name} = {
                enable = lib.mkEnableOption name;
              }
              // extraOptions;
            }
          );
        };

        config = lib.mkIf hasEnabled (
          lib.mkMerge (
            [ system ]
            ++ lib.optional (requires != [ ]) {
              modules.users = lib.mapAttrs (
                _: _:
                lib.genAttrs requires (_: {
                  enable = true;
                })
              ) enabledUsers;
            }
            ++ lib.optional hasUser {
              users.users = lib.mapAttrs (
                username: userCfg:
                let
                  cfg = userCfg.${name};
                in
                if isUserFn then user { inherit cfg username; } else user
              ) enabledUsers;
            }
            ++ [
              {
                home-manager.users = lib.mapAttrs (
                  username: userCfg:
                  let
                    cfg = userCfg.${name};
                  in
                  if isHomeFn then home { inherit cfg username; } else home
                ) enabledUsers;
              }
            ]
          )
        );
      }
    )
  ];
}
