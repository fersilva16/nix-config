_: {
  homebrew.casks = [ "stremio" ];

  system.activationScripts.postActivation.text = ''
    sudo codesign --force --deep --sign - /Applications/Stremio.app
  '';
}
