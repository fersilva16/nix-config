# The paths nix-config and Limi agree on, from Limi's
# rust/apps/limi/host.nix. Limi is not a flake input: it lives only in the
# user's Limi profile, which `limi switch` fills, so these are copied here.
# Keep them in step with Limi's.
{
  # Relative to $HOME: the Nix profile that holds the suite.
  profile = ".local/state/nix/profiles/limi";
  # Inside the profile: limi-path, the commands that would clash with the
  # host's own (the tmux shim, the wt and tmux tools, omo).
  path = "libexec/limi/path";
  # Inside the profile, on the hub's machine: limi-hub.
  hub = "bin/limi-hub";
  # Relative to $HOME, on the hub's machine: the notes vault limi-hub serves.
  notes = "notes";
  # Inside the profile: the POSIX sh file ~/.profile sources for Nalum's
  # agent PATH in agents/* sessions.
  agentProfile = "share/limi/agent-profile.sh";
  # Inside the profile: limi-chrome's native messaging host manifest and its
  # unpacked extension.
  chromeHostManifest = "share/limi-chrome/limi.chrome.json";
  chromeExtension = "share/limi-chrome/extension";
  # Relative to $HOME: the host's own tmux options for the mux.
  hostConf = ".config/limi/tmux.conf";
  # Relative to $HOME: Nalum's omo home.
  nalumHome = ".nalum";
  # Relative to $HOME, macOS: where Chrome looks for the manifest, and the
  # copy of the extension Chrome loads.
  chromeNativeHost = "Library/Application Support/Google/Chrome/NativeMessagingHosts/limi.chrome.json";
  chromeExtensionCopy = ".local/share/limi/chrome-extension";
  # Relative to $HOME, macOS: the signed limi-host in Limi.app.
  macHost = "Applications/Limi Apps/Limi.app/Contents/MacOS/limi-host";
  # Relative to $HOME, macOS: the signed limi-launcher in Limi Launcher.app.
  macLauncher = "Applications/Limi Apps/Limi Launcher.app/Contents/MacOS/limi-launcher";
}
