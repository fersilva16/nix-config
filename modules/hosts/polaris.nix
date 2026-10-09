{ mkNixOSHost }:
let
  fernando = import ../users/polaris-fernando.nix;
in
mkNixOSHost {
  hostName = "polaris";
  primaryUser = fernando;
  users = [ fernando ];

  extraModules = [
    ./polaris-disk.nix

    # Host specifics; hardware config is generated at install time
    # (nixos-generate-config) and picked up when present — pathExists is
    # false while the file is missing/untracked, so eval works either way.
  ]
  ++ (if builtins.pathExists ./polaris-hardware.nix then [ ./polaris-hardware.nix ] else [ ])
  ++ [
    (
      { pkgs, ... }:
      {
        boot = {
          # RTL8922AE WiFi does not probe on the default 6.18 kernel (no wifi
          # device at all; the 7.1.x install ISO worked). Track latest until
          # the default catches up. Known tension: Blackwell suspend-to-idle
          # hangs on the newest kernels — if that hits, weigh WiFi vs suspend.
          kernelPackages = pkgs.linuxPackages_latest;

          # RTL8922AE power saving causes 70 ms latency spikes to the router
          # and repeated "failed to update RXBD info: -11" in the kernel log.
          # Desktop, so no battery to save: keep the radio and PCIe link awake.
          extraModprobeConfig = ''
            options rtw89_core disable_ps_mode=y
            options rtw89_pci disable_aspm_l1=y disable_aspm_l1ss=y
          '';

          # Windows ESP lives on the other disk, so systemd-boot cannot
          # auto-detect it. Device handle discovered via the edk2 UEFI shell
          # (`map -c`, the FS whose \EFI contains Microsoft).
          loader.systemd-boot.windows."11".efiDeviceHandle = "HD0b";
        };
        networking.networkmanager.wifi.powersave = false;

        # Windows (separate disk) keeps the RTC in localtime; adjusting here
        # avoids registry surgery on the Windows side.
        time.hardwareClockInLocalTime = true;

        # CUDA cache (ollama-cuda; cache.nixos.org never has unfree CUDA).
        # Always on, not set by the ollama module: a module's nix.settings
        # only reach nix.conf after a successful switch, and enabling ollama
        # without the cache already present compiles CUDA from source. The
        # flake nixConfig copy does not help under a non-interactive sudo
        # rebuild, where untrusted flake settings are silently ignored.
        nix.settings = {
          substituters = [ "https://cache.nixos-cuda.org" ];
          trusted-public-keys = [ "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M=" ];
        };
      }
    )
  ];
}
