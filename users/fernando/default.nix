{ pkgs, ... }: {
  users.users.fernando = {
    isNormalUser = true;
    shell = pkgs.fish;
    extraGroups = [
      "wheel"
      "networkmanager"
      "video"
      "docker"
    ];
    # TODO: change the password
    initialPassword = "password";
  };
}
