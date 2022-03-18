{ ... }: {
  users.users.fernando = {
    isNormalUser = true;
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
