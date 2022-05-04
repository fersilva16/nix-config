self: super:
{
  kitty-themes = super.kitty-themes.overrideAttrs (_: {
    version = "2022-04-05";
    src = self.fetchFromGitHub {
      owner = "kovidgoyal";
      repo = "kitty-themes";
      rev = "0cc90555e3725b193785bc7e5266b27db5c08b2b";
      sha256 = "lq+VE/+BL7F0SKmNaXMKm/4cM9NVARKJzJThyLG5Ec4=";
    };
  });

  dmenu = import ./dmenu.nix self super;
} // import ../pkgs/pkgs.nix { inherit self; }
