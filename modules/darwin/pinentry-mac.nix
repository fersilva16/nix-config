{ username, ... }:
{
  homebrew.brews = [ "pinentry-mac" ];

  home-manager.users.${username} = {
    home.file.".gnupg/gpg-agent.conf" = {
      text = ''
        pinentry-program /usr/local/bin/pinentry-mac
      '';
    };
  };
}
