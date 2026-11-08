{ mkNixOSHost }:
let
  fernando = import ../users/altair-fernando.nix;
in
mkNixOSHost {
  hostName = "altair";
  primaryUser = fernando;
  users = [ fernando ];

  extraModules = [
    ./altair-disk.nix

    # Hardware config is generated at install time (nixos-generate-config)
    # and picked up when present, same as polaris.
  ]
  ++ (if builtins.pathExists ./altair-hardware.nix then [ ./altair-hardware.nix ] else [ ])
  ++ [
    {
      # Headless ThinkCentre M720q (i5-8400T, 8 GB, 256 GB NVMe): no desktop,
      # audio, GPU or wireless input, so the desktop-side system modules that
      # default to on stay off here.
      modules.system = {
        bluetooth.enable = false;
        pipewire.enable = false;
        nvidia.enable = false;
        logitech.enable = false;
        noctalia-greeter.enable = false;
        server-mode.enable = false;
        caskaydia-cove.enable = false;

        # A copy on another machine and disk: polaris's /data. altair is
        # always on, so it pushes and wakes polaris for it.
        backup.to = "polaris";
      };

      # Names and allowed values: ls /sys/class/firmware-attributes/thinklmi/attributes
      modules.system.bios.settings = {
        # A headless server comes back by itself after a power cut.
        "After Power Loss" = "Power On";
        # Woken from the LAN, boot the normal (primary) sequence.
        "Wake on LAN" = "Primary";
        # lanzaboote signs the boot chain (modules/linux/boot.nix).
        "Secure Boot" = "Enabled";
      };

      time.timeZone = "America/Sao_Paulo";

      # altair is deployed from another host (nixos-rebuild --target-host),
      # which copies unsigned, locally built paths in as fernando; the daemon
      # refuses those from an untrusted user. fernando has sudo here anyway.
      nix.settings.trusted-users = [ "fernando" ];
    }
  ];
}
