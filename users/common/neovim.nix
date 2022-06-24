{ pkgs, ... }:
let
  nvchad = pkgs.vimUtils.buildVimPluginFrom2Nix {
    pname = "nvchad";
    version = "2022-06-24";
    src = pkgs.fetchFromGitHub {
      owner = "NvChad";
      repo = "NvChad";
      rev = "5e4b2e6a117bd62a29f02b4825d1f1b1f2f21172";
      sha256 = "sha256-zuBzkfm3FKWM/LDut5Ry+I6aNA0kfGpOHLyG1GDTaVc=";
    };
  };
in
{
  programs.neovim = {
    enable = true;

    extraConfig = ''
      source ${nvchad}/init.lua
    '';

    plugins = [
      nvchad
    ];
  };
}
