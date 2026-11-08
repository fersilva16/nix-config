# Public keys of the hosts that push encrypted restic backups to a fleet
# peer's backup store (modules/linux/backup.nix). Each source host makes its
# own key on first boot at /var/lib/restic-backup/ssh_id_ed25519.pub; the
# store accepts it for SFTP into its chroot only.
[
]
