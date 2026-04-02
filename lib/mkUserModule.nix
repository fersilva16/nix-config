# mkUserModule — creates a unified module that handles both system-level
# and per-user home-manager config, with multi-user support.
#
# Each module declares an enable option under `modules.users.<name>.<moduleName>`.
# When any user enables it, system config runs once; home config runs per-user.
#
# Signature: { name, system?, home?, user?, extraOptions?, requires?, parts? } -> module
#
# Fields:
#
#   name:         Module name. Creates `modules.users.<user>.<name>.enable` option.
#
#   system:       (optional) System-level config applied once when any user enables
#                 the module. Always a static attrset.
#
#   home:         (optional) Per-user home-manager config. Can be an attrset (static)
#                 or a function ({ cfg, lib, username, userCfg } -> attrset) when
#                 per-user option values or cross-module checks are needed.
#                 Merged into home-manager.users.<username>.
#
#   user:         (optional) Per-user nix-darwin user account config. Can be an
#                 attrset (static) or a function ({ cfg, username } -> attrset).
#                 Merged into users.users.<username>. Use for per-user system-level
#                 settings like login shell.
#
#   extraOptions: (optional) Custom per-user option declarations (attrset of mkOption defs).
#
#   requires:     (optional) List of module names to auto-enable for every user
#                 who enables this module. Uses mkDefault so explicit
#                 `enable = false` in the user file can override. The required
#                 modules must be imported in the system — this only sets
#                 `enable = true`, it does not configure their extraOptions.
#
#   parts:        (optional) Sub-features that can be independently toggled.
#                 Each part is an attrset with optional fields:
#                   - default: bool (default true) — enabled by default when
#                     parent is enabled.
#                   - system: attrset — system config, applied once when any
#                     user enables this part.
#                   - home: attrset or function — per-user config. Function
#                     form receives { cfg, parentCfg, lib, username, userCfg }.
#                     cfg is the part's own config; parentCfg is the parent
#                     module's full config.
#                   - extraOptions: attrset — additional per-user option
#                     declarations for this part.
#                 Parts create nested options under the parent namespace:
#                   modules.users.<user>.<name>.<partName>.enable
#
# User composition (in user file):
#
#   modules.users.fernando = {
#     bat.enable = true;
#     git = { enable = true; userName = "Fernando"; userEmail = "..."; };
#     opencode = { enable = true; server.enable = false; };
#   };
#
{
  name,
  system ? { },
  home ? { },
  user ? { },
  extraOptions ? { },
  requires ? [ ],
  parts ? { },
}:
let
  isHomeFn = builtins.isFunction home;
  isUserFn = builtins.isFunction user;
  hasUser = user != { } || isUserFn;
  hasParts = parts != { };
in
{
  imports = [
    (
      { config, lib, ... }:
      let
        enabledUsers = lib.filterAttrs (_: u: u.${name}.enable) config.modules.users;
        hasEnabled = enabledUsers != { };

        # Build option declarations for each part: { partName = { enable = ...; } // partExtraOptions; }
        partOptions = lib.mapAttrs (
          partName: partDef:
          {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = partDef.default or true;
              description = "Enable ${name} ${partName} sub-feature.";
            };
          }
          // (partDef.extraOptions or { })
        ) parts;
      in
      {
        options.modules.users = lib.mkOption {
          type = lib.types.attrsOf (
            lib.types.submodule (
              { config, ... }:
              {
                options.${name} = {
                  enable = lib.mkEnableOption name;
                }
                // extraOptions
                // partOptions;

                # requires: when this module is enabled, auto-enable dependencies.
                # Resolved inside the submodule so there's no read/write cycle on
                # the top-level modules.users option.
                config = lib.mkIf (requires != [ ] && config.${name}.enable) (
                  lib.genAttrs requires (_: {
                    enable = lib.mkDefault true;
                  })
                );
              }
            )
          );
        };

        config = lib.mkIf hasEnabled (
          lib.mkMerge (
            [ system ]

            # Part system configs: applied once when any enabled user has the part enabled
            ++ lib.optionals hasParts (
              lib.mapAttrsToList (
                partName: partDef:
                let
                  partSys = partDef.system or { };
                  partUsers = lib.filterAttrs (_: u: u.${name}.${partName}.enable) enabledUsers;
                in
                lib.mkIf (partUsers != { }) partSys
              ) parts
            )

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
                    baseHome =
                      if isHomeFn then
                        home {
                          inherit
                            cfg
                            lib
                            username
                            userCfg
                            ;
                        }
                      else
                        home;

                    # Collect enabled parts' home configs and merge with base
                    partHomes = lib.optionals hasParts (
                      lib.mapAttrsToList (
                        partName: partDef:
                        let
                          partHome = partDef.home or { };
                          isPartHomeFn = builtins.isFunction partHome;
                          partCfg = cfg.${partName};
                        in
                        lib.mkIf partCfg.enable (
                          if isPartHomeFn then
                            partHome {
                              cfg = partCfg;
                              parentCfg = cfg;
                              inherit lib username userCfg;
                            }
                          else
                            partHome
                        )
                      ) parts
                    );
                  in
                  lib.mkMerge ([ baseHome ] ++ partHomes)
                ) enabledUsers;
              }
            ]
          )
        );
      }
    )
  ];
}
