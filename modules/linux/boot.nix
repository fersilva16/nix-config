# systemd-boot under Secure Boot for NixOS hosts, via lanzaboote — no GRUB.
#
# lanzaboote replaces the systemd-boot installer: it signs systemd-boot and
# one UKI per generation with this host's own keys (/var/lib/sbctl). The
# keys are created on first boot (generate-sb-keys.service) and enrolled by
# systemd-boot on the next boot, but only while the firmware is in Setup
# Mode. Microsoft's keys are enrolled alongside, for Windows and for GPU
# option ROMs. Check the state with `sbctl status`.
#
# Anything else on the ESP must be signed with the same key to boot, so
# there is no UEFI shell entry: a signed shell would let anyone at the
# keyboard bypass Secure Boot.
{
  mkSystemModule,
  pkgs,
  lib,
  ...
}:
mkSystemModule {
  name = "boot";

  extraOptions.windows.enable = lib.mkEnableOption "the `boot-windows` command (Windows on its own disk)";

  config =
    { config, cfg, ... }:
    let
      esp = config.boot.loader.efi.efiSysMountPoint;
      inherit (config.boot.lanzaboote) privateKeyFile publicKeyFile;

      # Windows lives on its own disk with its own ESP, so systemd-boot
      # cannot chainload it without the (unsigned) UEFI shell. Boot it
      # through the firmware's own "Windows Boot Manager" entry instead:
      # BootNext is a one-shot override, and bootmgfw is Microsoft-signed.
      # ponytail: takes the first matching entry; add a picker if a second
      # Windows install ever shows up.
      boot-windows = pkgs.writeShellApplication {
        name = "boot-windows";
        runtimeInputs = [ pkgs.efibootmgr ];
        text = ''
          num=$(efibootmgr | sed -n 's/^Boot\([0-9A-Fa-f]\{4\}\)\*\{0,1\} Windows Boot Manager.*/\1/p' | head -n 1)
          if [ -z "$num" ]; then
            echo "boot-windows: no 'Windows Boot Manager' firmware boot entry" >&2
            exit 1
          fi
          sudo efibootmgr --quiet --bootnext "$num"
          exec systemctl reboot
        '';
      };
    in
    {
      boot = {
        lanzaboote = {
          enable = true;
          pkiBundle = "/var/lib/sbctl";
          autoGenerateKeys.enable = true;
          autoEnrollKeys.enable = true;
        };

        loader = {
          # Not enabled: lanzaboote installs it. consoleMode, editor,
          # configurationLimit and loader.timeout still feed its loader.conf.
          systemd-boot = {
            consoleMode = "max";
            editor = false;
            configurationLimit = 20;
          };
          efi.canTouchEfiVariables = true;
          # Skip the menu; hold Space at boot to show it. `boot-windows`
          # covers the usual reason to pick an entry.
          timeout = 0;
        };
      };

      # Offline RAM test, no USB stick needed. Reach it with
      # `systemctl reboot --boot-loader-entry=memtest86.conf`.
      # lanzaboote installs no extra files, so this service puts memtest on
      # the ESP signed with the host key, the same way lanzaboote signs
      # fwupd's EFI app. It reruns on every switch that changes memtest.
      # Boot options: nobigstatus keeps the PASS/FAIL banner from covering
      # the error details, which matters when the keyboard does not work in
      # memtest to dismiss it; usbinit=3 is its USB keyboard workaround.
      systemd.services.memtest-esp = {
        description = "Install signed Memtest86+ on the ESP";
        wantedBy = [ "multi-user.target" ];
        after = [ "generate-sb-keys.service" ];
        unitConfig.ConditionPathExists = privateKeyFile;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          mkdir -p ${esp}/efi/memtest86 ${esp}/loader/entries
          ${lib.getExe' pkgs.sbsigntool "sbsign"} --key '${privateKeyFile}' --cert '${publicKeyFile}' \
            --output ${esp}/efi/memtest86/memtest.efi ${pkgs.memtest86plus.efi}
          cat > ${esp}/loader/entries/memtest86.conf <<'EOF'
          title Memtest86+
          efi /efi/memtest86/memtest.efi
          options nobigstatus usbinit=3
          sort-key o_memtest86
          EOF
        '';
      };

      environment.systemPackages = [ pkgs.sbctl ] ++ lib.optional cfg.windows.enable boot-windows;
    };
}
