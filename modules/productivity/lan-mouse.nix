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
# darwin: a launchd agent runs the store binary. macOS gates its event tap
# behind Accessibility for that exact binary, so a lan-mouse update (new
# store path) needs the permission granted again.
# linux: a user service bound to the graphical session. niri provides the
# layer-shell capture and wlroots virtual-pointer/keyboard emulation.
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
    ];
  });
  exe = lib.getExe lan-mouse;
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

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Run lan-mouse for the whole session. When false the service is still
        installed but only runs once started by hand (launchctl kickstart /
        systemctl --user start), and stays stopped once stopped.
      '';
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
      linux.networking.firewall.allowedUDPPorts = [ port ];
    };

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
          clients = lib.mapAttrsToList (name: position: {
            inherit position;
            hostname = "${name}.local";
            activate_on_startup = true;
          }) cfg.peers;
          authorized_fingerprints = lib.mapAttrs' (
            name: _: lib.nameValuePair fleetPeers.${name}.lanMouse.${username} name
          ) cfg.peers;
        }
        // cfg.settings
      );

      # Without autoStart, "Toggle Lan Mouse" in Vicinae starts/stops it.
      home.file.".local/share/vicinae/scripts/lan-mouse.sh" =
        lib.mkIf (userCfg.vicinae.enable && !cfg.autoStart)
          {
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
            exe
            "daemon"
          ];
          RunAtLoad = cfg.autoStart;
          KeepAlive = cfg.autoStart;
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
        Install = lib.mkIf cfg.autoStart { WantedBy = [ "graphical-session.target" ]; };
      };
    };
}
