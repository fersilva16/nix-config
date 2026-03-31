# mkUserModule — creates a unified module that handles both system-level
# and per-user home-manager config, with multi-user support.
#
# Each module declares an enable option under `modules.users.<name>.<moduleName>`.
# When any user enables it, system config runs once; home config runs per-user.
#
# Signature: { name, system?, home?, extraOptions?, requires? } -> module
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
#                 values are needed.
#
#   extraOptions: (optional) Custom per-user option declarations (attrset of mkOption defs).
#
#   requires:     (optional) List of module names to auto-enable for every user
#                 who enables this module. The required modules must be imported
#                 in the system — this only sets `enable = true`, it does not
#                 configure their extraOptions (users set those, or defaults apply).
#
# Usage:
#
#   # Simple HM-only:
#   { mkUserModule, ... }:
#   mkUserModule {
#     name = "bat";
#     home.programs.bat.enable = true;
#   }
#
#   # System-only cask:
#   { mkUserModule, ... }:
#   mkUserModule {
#     name = "slack";
#     system.homebrew.casks = [ "slack" ];
#   }
#
#   # Unified system + user:
#   { mkUserModule, pkgs, ... }:
#   mkUserModule {
#     name = "fish";
#     system = {
#       environment.systemPackages = [ pkgs.fish ];
#       programs.fish.enable = true;
#     };
#     home.programs.fish = {
#       enable = true;
#       shellAliases = { ll = "eza -la"; };
#     };
#   }
#
#   # With custom per-user options:
#   { mkUserModule, lib, ... }:
#   mkUserModule {
#     name = "bat";
#     extraOptions.fishAlias = lib.mkOption {
#       type = lib.types.bool;
#       default = true;
#       description = "Whether to alias cat to bat in fish shell.";
#     };
#     home = { cfg, ... }: {
#       programs.bat.enable = true;
#       programs.fish.shellAliases = lib.mkIf cfg.fishAlias {
#         cat = "bat";
#       };
#     };
#   }
#
#   # With required dependencies:
#   { mkUserModule, ... }:
#   mkUserModule {
#     name = "1password";
#     requires = [ "git" ];
#     system.homebrew.casks = [ "1password" ];
#     home = { ... }: { ... };
#   }
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
  extraOptions ? { },
  requires ? [ ],
}:
let
  isFn = builtins.isFunction home;
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
          default = { };
        };

        config = lib.mkIf hasEnabled (
          lib.mkMerge [
            system
            (lib.optionalAttrs (requires != [ ]) {
              modules.users = lib.mapAttrs (
                _: _:
                lib.genAttrs requires (_: {
                  enable = true;
                })
              ) enabledUsers;
            })
            {
              home-manager.users = lib.mapAttrs (
                username: userCfg:
                let
                  cfg = userCfg.${name};
                in
                if isFn then home { inherit cfg username; } else home
              ) enabledUsers;
            }
          ]
        );
      }
    )
  ];
}
