self: super:
{
  kitty-themes = import ./kitty-themes.nix self super;
  dmenu = import ./dmenu.nix self super;
  discord = import ./discord.nix self super;
} // import ../pkgs/pkgs.nix self
