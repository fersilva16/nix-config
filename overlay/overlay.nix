self: super:
{
  kitty-themes = import ./kitty-themes.nix self super;
  dmenu = import ./dmenu.nix self super;
  discord = import ./discord.nix self super;
  noto-fonts-cjk-sans = import ./noto-fonts-cjk-sans.nix self super;
  noto-fonts-cjk-serif = import ./noto-fonts-cjk-serif.nix self super;
} // import ../pkgs/pkgs.nix self
