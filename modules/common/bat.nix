{ username, ... }: {
  home-manager.users.${username} = { programs.bat = { enable = true; }; };
}
