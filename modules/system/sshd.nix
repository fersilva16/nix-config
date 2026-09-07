# SSH daemon hardening, expressed per platform because the two OSes take it
# by different routes:
#
#   darwin — the daemon itself is toggled on demand by tmux-remote (Remote
#     Login), so only the drop-in is declared. macOS sshd_config ends with an
#     Include of sshd_config.d/*, which is what makes this file take effect.
#
#   linux — NixOS generates sshd_config wholesale from services.openssh and
#     emits no sshd_config.d include, so the same rules have to be settings.
#     The daemon IS declared here: polaris is reached over SSH by design.
#
# Kerberos/GSSAPI are omitted on linux rather than disabled: both already
# default to no in OpenSSH, and naming a directive the local build lacks
# fails sshd's config check at build time.
{ mkSystemModule, forPlatform, ... }:
mkSystemModule {
  name = "sshd";
  config = forPlatform {
    darwin.environment.etc."ssh/sshd_config.d/200-hardening.conf" = {
      text = ''
        # Key-only authentication — no passwords, no keyboard-interactive
        PubkeyAuthentication yes
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
