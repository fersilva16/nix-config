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
      };

      time.timeZone = "America/Sao_Paulo";
    }
  ];
}
