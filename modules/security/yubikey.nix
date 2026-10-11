{
  mkUserModule,
  forPlatform,
  lib,
  pkgs,
  ...
}:
mkUserModule {
  name = "yubikey";
  casks = [ "yubico-authenticator" ];

  extraOptions.u2fKeys = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = ''
      pam_u2f credentials: `pamu2fcfg` output without the leading `<user>:`.
      Public data. Non-empty turns on touch-to-authenticate on linux.
    '';
  };

  # Touch ID, YubiKey edition: sudo and the noctalia lock screen ask for a
  # touch first and fall back to the password when the key is absent or not
  # touched. greetd stays password-only (its password unlocks gnome-keyring),
  # and it pulls in `login` as a substack, so the lock screen gets its own
  # service instead of noctalia's default `login`.
  system =
    { enabledUsers }:
    let
      withKeys = lib.filterAttrs (_: u: u.yubikey.u2fKeys != [ ]) enabledUsers;
      noctalia = lib.any (u: u.noctalia.enable or false) (lib.attrValues withKeys);
    in
    forPlatform {
      linux = lib.mkIf (withKeys != { }) {
        security.pam.u2f.settings = {
          authfile = pkgs.writeText "u2f_keys" (
            lib.concatStrings (
              lib.mapAttrsToList (name: u: "${name}:${lib.concatStringsSep ":" u.yubikey.u2fKeys}\n") withKeys
            )
          );
          cue = true;
        };
        security.pam.services = {
          sudo.u2fAuth = true;
          noctalia-lock = lib.mkIf noctalia { u2fAuth = true; };
        };
        environment.sessionVariables = lib.mkIf noctalia {
          NOCTALIA_PAM_SERVICE = "noctalia-lock";
        };
      };
    };
}
