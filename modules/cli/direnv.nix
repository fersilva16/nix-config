{ mkUserModule, inputs, ... }:
mkUserModule {
  name = "direnv";
  home = {
    imports = [
      inputs.direnv-instant.homeModules.direnv-instant
    ];

    programs.direnv-instant.enable = true;

    programs.direnv = {
      nix-direnv.enable = true;
      config.global.hide_env_diff = true;
    };
  };
}
