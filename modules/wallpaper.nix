{ lib, ... }:
{
  options = {
    wallpaper = lib.mkOption {
      type = lib.types.path;
    };
  };
}
