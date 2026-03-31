{ mkUserModule, ... }:
mkUserModule {
  name = "1password";
  system.homebrew.casks = [
    "1password"
    "1password-cli"
  ];
}
