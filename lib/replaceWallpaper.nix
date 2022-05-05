{ config }:
builtins.replaceStrings [ "%wallpaper%" ] [ (toString config.wallpaper) ]
