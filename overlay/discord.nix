let
  version = "0.0.18";
in
self: super:
super.discord.overrideAttrs (_: {
  inherit version;
  src = self.fetchurl {
    url = "https://dl.discordapp.net/apps/linux/${version}/discord-${version}.tar.gz";
    sha256 = "sha256-BBc4n6Q3xuBE13JS3gz/6EcwdOWW57NLp2saOlwOgMI=";
  };
})
