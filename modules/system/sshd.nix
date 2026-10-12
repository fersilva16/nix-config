# SSH daemon hardening, expressed per platform because the two OSes take it
# by different routes:
#
#   darwin — services.openssh.enable turns Remote Login on (launchctl, not
#     the Sharing toggle). Apple's sshd is inetd-style: launchd holds :22 and
#     spawns sshd per connection, so nothing runs while idle. The rules are a
#     drop-in: macOS sshd_config Includes sshd_config.d/* above its own
#     settings, and the first value sshd reads wins. Keys come only from
#     users.users.<name>.openssh.authorizedKeys (modules/cli/ssh.nix), which
#     nix-darwin serves through AuthorizedKeysCommand; `AuthorizedKeysFile
#     none` stops ~/.ssh/authorized_keys from adding keys nix doesn't know.
#
#   linux — NixOS generates sshd_config wholesale from services.openssh and
#     emits no sshd_config.d include, so the same rules have to be settings.
#
# Both advertise "ssh" to the fleet, which gives every peer an ssh Host block
# and a tmux hop target for this machine.
#
# Kerberos/GSSAPI are omitted on linux rather than disabled: both already
# default to no in OpenSSH, and naming a directive the local build lacks
# fails sshd's config check at build time.
{ mkSystemModule, forPlatform, ... }:
mkSystemModule {
  name = "sshd";
  config = {
    fleet.services = [ "ssh" ];
  }
  // forPlatform {
    darwin.services.openssh.enable = true;
    darwin.environment.etc."ssh/sshd_config.d/200-hardening.conf" = {
      text = ''
        # Key-only authentication — no passwords, no keyboard-interactive
        PubkeyAuthentication yes
        AuthorizedKeysFile none
        PasswordAuthentication no
        KbdInteractiveAuthentication no
        PermitEmptyPasswords no

        # No root login
        PermitRootLogin no

        # Limit authentication attempts
        MaxAuthTries 3
        MaxSessions 5
        LoginGraceTime 30

        # Disable unused auth methods
        HostbasedAuthentication no
        KerberosAuthentication no
        GSSAPIAuthentication no
      '';
    };

    linux.services.openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitEmptyPasswords = false;
        PermitRootLogin = "no";
        MaxAuthTries = 3;
        MaxSessions = 5;
        LoginGraceTime = 30;
        HostbasedAuthentication = false;
      };
    };
  };
}
