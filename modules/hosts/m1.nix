_: {
  networking.hostName = "m1";
  system.primaryUser = "fernando";
  system.stateVersion = 5;

  imports = [
    ../users/m1-fernando.nix
  ];
}
