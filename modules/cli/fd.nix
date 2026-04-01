{
  mkUserModule,
  ...
}:
mkUserModule {
  name = "fd";
  home.programs.fd.enable = true;
}
