_: {
  environment.etc."ssh/sshd_config.d/200-hardening.conf" = {
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
}
