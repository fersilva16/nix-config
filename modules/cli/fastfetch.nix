{ mkUserModule, ... }:
mkUserModule {
  name = "fastfetch";
  home.programs.fastfetch.enable = true;
}
