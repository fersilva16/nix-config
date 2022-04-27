{ ... }:
{
  home.file.".gnupg/gpg-agent.conf".text = ''
    default-cache-ttl 14400
    allow-emacs-pinentry
  '';
}
