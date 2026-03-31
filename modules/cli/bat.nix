{ mkUserModule, lib, ... }:
mkUserModule {
  name = "bat";
  extraOptions.fishAlias = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Whether to alias cat to bat in fish shell.";
  };
  home =
    { cfg, ... }:
    {
      programs.bat.enable = true;
      programs.fish.shellAliases = lib.mkIf cfg.fishAlias {
        cat = "bat";
      };
    };
}
