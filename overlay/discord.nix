let
  version = "0.0.20";
in
self: super:
super.discord.overrideAttrs (_: {
  inherit version;
  src = self.fetchurl {
    url = "https://dl.discordapp.net/apps/linux/${version}/discord-${version}.tar.gz";
    sha256 = "sha256-3f7yuxigEF3e8qhCetCHKBtV4XUHsx/iYiaCCXjspYw=";
  };
})
