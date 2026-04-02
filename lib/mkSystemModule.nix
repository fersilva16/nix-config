# mkSystemModule — creates a system-level module with an enable option
# under `modules.system.<name>`.
#
# Unlike mkUserModule (per-user opt-in), this is host-wide infrastructure.
# All system modules default to enabled; hosts can opt out selectively.
#
# Signature: { name, config?, extraOptions? } -> module
#
# Fields:
#
#   name:         Module name. Creates `modules.system.<name>.enable` option.
#
#   config:       (optional) System config applied when enabled. Can be a
#                 static attrset or a function ({ config, cfg, lib } -> attrset)
#                 when access to the evaluated host config or module options
#                 is needed. `cfg` is the module's own config
#                 (`modules.system.<name>`).
#
#   extraOptions: (optional) Custom options under `modules.system.<name>`.
#
# Usage:
#
#   # Static config (pkgs from outer module scope):
#   { mkSystemModule, pkgs, ... }:
#   mkSystemModule {
#     name = "wget";
#     config.environment.systemPackages = [ pkgs.wget ];
#   }
#
#   # Dynamic config (needs evaluated host config):
#   { mkSystemModule, inputs, ... }:
#   mkSystemModule {
#     name = "homebrew";
#     config = { config, ... }: {
#       nix-homebrew.user = config.system.primaryUser;
#     };
#   }
#
#   # Opt-out per host:
#   modules.system.sudo-touchid.enable = false;
#
{
  name,
  config ? { },
  extraOptions ? { },
}:
let
  isConfigFn = builtins.isFunction config;
  moduleConfig = config;
in
{
  imports = [
    (
      { config, lib, ... }:
      let
        cfg = config.modules.system.${name};
        resolvedConfig =
          if isConfigFn then
            moduleConfig {
              inherit config cfg lib;
            }
          else
            moduleConfig;
      in
      {
        options.modules.system.${name} = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable ${name} system module.";
          };
        }
        // extraOptions;

        config = lib.mkIf cfg.enable resolvedConfig;
      }
    )
  ];
}
