{ mkUserModule, forPlatform, ... }:
mkUserModule {
  name = "stremio";
  casks = [ "stremio" ];
  system = forPlatform {
    darwin = {
      system.activationScripts.postActivation.text = ''
        sudo codesign --force --deep --sign - /Applications/Stremio.app
        sudo xattr -rd com.apple.quarantine /Applications/Stremio.app
      '';
    };
  };
}
