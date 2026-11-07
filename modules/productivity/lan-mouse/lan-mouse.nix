# lan-mouse — software KVM: one keyboard + mouse drives every host, and the
# pointer moves to the next machine at a screen edge. The release bind
# (default Ctrl+Shift+Meta+Alt) pulls input back if it gets stuck remote.
#
# Traffic is DTLS, and a peer is only accepted when its certificate
# fingerprint is authorized. Each host generates
# ~/.config/lan-mouse/lan-mouse.pem on first start and keeps it; a new cert
# (wiped home, reinstall) means updating `fingerprint` in that host's user
# file, which advertises it to the fleet (modules/system/fleet.nix):
#   openssl x509 -in ~/.config/lan-mouse/lan-mouse.pem -noout -fingerprint -sha256 | cut -d= -f2 | tr A-F a-f
#
# config.toml is nix-owned and read-only, so peers added or authorized from
# the GUI do not persist: declare them in `peers`.
#
# darwin: macOS gates the event tap behind Accessibility, and an ad-hoc
# signed binary is identified by its hash, so every new build would need
# the permission granted again (one more "lan-mouse" row each time).
# Activation copies the binary to a fixed root-owned path and re-signs it
# with a name-based identity; the launchd agent runs that copy, so one
# grant for /usr/local/libexec/lan-mouse survives updates. Only root can
# replace the file the grant is tied to.
# linux: a user service bound to the graphical session. niri provides the
# layer-shell capture and wlroots virtual-pointer emulation. Keys go out
# through the patched-in `uinput` backend instead (./uinput-emulation.patch):
# wlroots' virtual keyboard feeds niri directly, so evdev remappers (xremap)
# never saw remote keystrokes. A uinput device is a real evdev keyboard
# that xremap grabs like a physical one.
#
# Remapping happens on the receiving side only: the sender forwards raw keys
# and the receiver runs them through its own remapper, so one keyboard means
# the same thing on both hosts. Caps Lock is F18 at the kernel on both
# (hidutil on darwin, udev hwdb in modules/linux/xremap/hyper.nix), so the
# hyper key crosses as F18 and never toggles the sender's caps lock.
#   - darwin sender: the capture tap sits at the HID level, ahead of
#     Hammerspoon's session-level tap, so hyper never sees outgoing keys.
#   - linux sender: xremap grabs the keyboard below niri, where lan-mouse
#     captures, so the enter/leave hooks stop xremap while keys go remote.
{
  mkUserModule,
  forPlatform,
  pkgs,
  lib,
  fleetPeers,
  ...
}:
let
  port = 4242;
  toml = pkgs.formats.toml { };

  # 0.11.0 resolves peer hostnames with a pure-DNS client, which misses
  # mDNS: `polaris.local` / `vega.local` never resolve. Upstream a42592a
  # moved to the OS resolver (Bonjour on darwin, nss-mdns via avahi on
  # linux); backported until nixpkgs ships a release with it. Its lockfile
  # half is skipped: the now-unused hickory crate just stays vendored.
  # leave_hook (upstream 9b2b813 + a78362b, after 0.11.0) is what lets a
  # linux sender start xremap again once keys come back.
  # Upstream spawns each hook detached, so a reconnect that fires enter and
  # leave together can finish `stop xremap` last and leave the keyboard
  # unmapped; ./ordered-hooks.patch runs them one at a time, in order.
  lan-mouse = pkgs.lan-mouse.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      (pkgs.fetchpatch {
        url = "https://github.com/feschber/lan-mouse/commit/a42592ab055e2fdad6b6545de5a849a3fefeeff1.patch";
        includes = [
          "src/dns.rs"
          "src/service.rs"
        ];
        hash = "sha256-eysZHWV1u1pcg8nv6O6RR79qERUrfv0pjOVMOU+0Xns=";
      })
      ./uinput-emulation.patch
      (pkgs.fetchpatch {
        url = "https://github.com/feschber/lan-mouse/commit/9b2b813c0517eee4966c3f042a8f9678885a73f4.patch";
        excludes = [ "config.toml" ];
        hash = "sha256-SfVqjBfReCJdwIdHFCVfF/ji0HLRVJmYRKN2dD6UtrQ=";
      })
      (pkgs.fetchpatch {
        url = "https://github.com/feschber/lan-mouse/commit/a78362b56e8249c79e4d48b801216ede31e24086.patch";
        hash = "sha256-+0uZUZSw2qHhgDKy3qWMx46CN9IcOgCsFEyguXVkr54=";
      })
      ./macos-modifiers.patch
      ./ordered-hooks.patch
    ];
    # Upstream taps at the session level, where Hammerspoon's hyper tap also
    # sits; whichever was inserted last runs first, and Hammerspoon recreates
    # its tap every 30s. At the HID level lan-mouse always sees keys first.
    # Scroll from a remote mouse arrives in the protocol's positive-down sign
    # and 0.11.0 posts it to Quartz (positive-up) as is, so it scrolls the
    # natural way. Scroll Reverser leaves app-posted scroll unchanged, so
    # flip both axes here: a remote mouse scrolls classic, like the local
    # one does through Scroll Reverser. Upstream is still settling this
    # (feschber/lan-mouse#498, #537); recheck when nixpkgs bumps lan-mouse.
    postPatch = (old.postPatch or "") + ''
      substituteInPlace input-capture/src/macos.rs \
        --replace-fail "CGEventTapLocation::Session," "CGEventTapLocation::HID,"
      substituteInPlace input-emulation/src/macos.rs \
        --replace-fail "let value = value as i32;" "let value = -(value as i32);" \
        --replace-fail "value / (120 / LINES_PER_STEP)" "-value / (120 / LINES_PER_STEP)"
    '';
  });
  exe = lib.getExe lan-mouse;
  # The daemon needs none of the GTK env the wrapper sets, so the signed
  # copy is the unwrapped binary.
  darwinExe = "/usr/local/libexec/lan-mouse";
  signingId = "org.nix-config.lan-mouse";
in
mkUserModule {
  name = "lan-mouse";

  extraOptions = {
    peers = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.enum [
          "left"
          "right"
          "top"
          "bottom"
        ]
      );
      default = { };
      example.polaris = "left";
      description = ''
        Fleet machines (modules/hosts/fleet.nix) to share input with, each
        mapped to the screen edge it sits at. Reached at <name>.local and
        accepted by the `fingerprint` that machine advertises for this user.
      '';
    };

    fingerprint = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        This machine's certificate fingerprint for this user (see the header
        for how to read it). Advertised to the fleet so peers listing this
        machine in `peers` accept it.
      '';
    };

    settings = lib.mkOption {
      inherit (toml) type;
      default = { };
      description = "Extra config.toml keys, merged over the ones generated from `peers`.";
    };
  };

  system =
    { enabledUsers }:
    {
      fleet.lanMouse = lib.mapAttrs (_: u: u.lan-mouse.fingerprint) (
        lib.filterAttrs (_: u: u.lan-mouse.fingerprint != null) enabledUsers
      );
    }
    // forPlatform {
      # mkBefore: runs ahead of home-manager's activation, which (re)starts
      # the agent.
      darwin.system.activationScripts.postActivation.text = lib.mkBefore ''
        install -d /usr/local/libexec
        install -m 755 ${lan-mouse}/bin/.lan-mouse-wrapped ${darwinExe}
        /usr/bin/codesign --force --sign - --identifier ${signingId} \
          -r='designated => identifier "${signingId}"' ${darwinExe}
      '';
      linux = {
        networking.firewall.allowedUDPPorts = [ port ];
        hardware.uinput.enable = true;
      };
    };
  user = forPlatform { linux.extraGroups = [ "uinput" ]; };

  home =
    {
      cfg,
      username,
      userCfg,
      ...
    }:
    {
      home.packages = [ lan-mouse ];
      xdg.configFile."lan-mouse/config.toml".source = toml.generate "lan-mouse.toml" (
        {
          inherit port;
          clients = lib.mapAttrsToList (
            name: position:
            {
              inherit position;
              hostname = "${name}.local";
              activate_on_startup = true;
            }
            // forPlatform {
              # xremap is a linux-only module: no option to read on darwin.
              linux = lib.optionalAttrs (userCfg.xremap.enable or false) {
                enter_hook = "/run/current-system/sw/bin/systemctl --user stop xremap";
                leave_hook = "/run/current-system/sw/bin/systemctl --user start xremap";
              };
            }
          ) cfg.peers;
          authorized_fingerprints = lib.mapAttrs' (
            name: _: lib.nameValuePair fleetPeers.${name}.lanMouse.${username} name
          ) cfg.peers;
        }
        // forPlatform { linux.emulation_backend = "uinput"; }
        // cfg.settings
      );

      # Never auto-started: "Toggle Lan Mouse" in Vicinae starts/stops it.
      home.file.".local/share/vicinae/scripts/lan-mouse.sh" = lib.mkIf userCfg.vicinae.enable {
        executable = true;
        text = ''
          #!/bin/sh
          # @vicinae.schemaVersion 1
          # @vicinae.title Toggle Lan Mouse
          # @vicinae.mode compact
          # @vicinae.icon 🖱️
          # @vicinae.keywords ["kvm", "mouse", "keyboard", "share"]
        ''
        + forPlatform {
          darwin = ''
            s="gui/$(/usr/bin/id -u)/org.nix-community.home.lan-mouse"
            if /bin/launchctl print "$s" | /usr/bin/grep -q 'state = running'; then
              /bin/launchctl kill TERM "$s" && echo "Lan Mouse off"
            else
              /bin/launchctl kickstart "$s" && echo "Lan Mouse on"
            fi
          '';
          linux = ''
            systemctl=/run/current-system/sw/bin/systemctl
            if $systemctl --user is-active -q lan-mouse; then
              $systemctl --user stop lan-mouse && echo "Lan Mouse off"
            else
              $systemctl --user start lan-mouse && echo "Lan Mouse on"
            fi
          '';
        };
      };
    }
    // forPlatform {
      darwin.launchd.agents.lan-mouse = {
        enable = true;
        config = {
          ProgramArguments = [
            darwinExe
            "daemon"
          ];
          # The path above never changes; this does per build, so an update
          # reloads the agent onto the new binary.
          EnvironmentVariables.LAN_MOUSE_BUILD = "${lan-mouse}";
          ProcessType = "Interactive";
          StandardErrorPath = "/Users/${username}/Library/Logs/lan-mouse.log";
        };
      };

      linux.systemd.user.services.lan-mouse = {
        Unit = {
          Description = "Lan Mouse";
          After = [ "graphical-session.target" ];
          PartOf = [ "graphical-session.target" ];
        };
        Service = {
          ExecStart = "${exe} daemon";
          Restart = "on-failure";
        };
      };
    };
}
