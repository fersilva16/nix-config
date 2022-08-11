let
  version = "0.0.19";
in
self: super:
super.discord.overrideAttrs (_: {
  inherit version;
  src = self.fetchurl {
    url = "https://dl.discordapp.net/apps/linux/${version}/discord-${version}.tar.gz";
    sha256 = "sha256-GfSyddbGF8WA6JmHo4tUM27cyHV5kRAyrEiZe1jbA5A=";
  };
})
