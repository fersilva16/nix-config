{ ... }: {
  users.users.fernando = {
    isNormalUser = true;
    extraGroups = [
      "networkmanager"
      "video"
      "wheel"
      "docker"
    ];
    # TODO: change the password
    initialPassword = "password";
  };
}
