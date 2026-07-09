{ mkUser, ... }:
mkUser {
  name = "fernando";

  # Shell & CLI
  atuin.enable = true;
  bat.enable = true;
  ssh.enable = true;
  fish.enable = true;
  starship.enable = true;
  direnv.enable = true;
  tmux.enable = true;
  worktree.enable = true;
  zoxide.enable = true;
  eza.enable = true;
  fzf.enable = true;
  fd.enable = true;
  ripgrep.enable = true;
  chrome-cli.enable = true;
  readwise.enable = true;

  # Dev tools
  git.enable = true;
  lazygit.enable = true;
  awscli.enable = true;
  flyctl.enable = true;
  mongosh.enable = true;
  stern.enable = true;
  dbeaver.enable = true;
  "studio-3t".enable = true;
  postman.enable = true;
  ngrok.enable = true;
  orbstack.enable = true;
  "java-25".enable = true;
  minikube.enable = true;
  doppler.enable = true;
  claude.enable = true;
  "claude-code".enable = true;
  opencode = {
    enable = true;
    server.autoAttach = false;
  };
  playwright-cli.enable = true;
  opencode-manager.enable = true;
  # rtk.enable = true;
  ollama.enable = true;
  # hermes.enable = true;
  linear.enable = true;

  # Editors
  nvim.enable = true;
  vscode.enable = true;
  cursor.enable = false;
  intellij.enable = true;
  "android-studio".enable = true;

  # Browsers
  # Firefox stays installed as a secondary browser, but its per-profile .app
  # bundles are gone — Chrome is now the primary browser and Finicky routes to
  # Chrome profiles natively (see below).
  firefox.enable = true;
  chrome.enable = true;

  # URL router — set Finicky as the default browser so links from Slack/email/etc
  # route to the right Chrome profile instead of piling into one.
  #
  # Finicky opens Google Chrome with a specific profile via its native
  # `profile` support, which resolves the profile's display name against
  # Chrome's Local State and launches with `--profile-directory`. Profile
  # display names (not the on-disk "Profile N" dirs):
  #   "Personal"  → fernandonsilva16@gmail.com   (Chrome dir "Profile 2")
  #   "Telepatia" → fernando.silva@telepatia.ai  (Chrome dir "Profile 1")
  finicky = {
    enable = true;
    hideIcon = true;
    # Unmatched URLs open in Chrome's last-active profile. Launching Chrome
    # without a `--profile-directory` (i.e. no `defaultBrowserProfile`) makes
    # it route the URL to the most-recently-used Chrome window, so the
    # fallback "follows" whichever profile you were last in — the same
    # behavior the old Firefox active-profile router provided, but native to
    # Chrome and with no Hammerspoon involved. (Caveat: an incognito window is
    # skipped — Chrome opens a regular window of that profile instead.)
    defaultBrowser = "Google Chrome";
    handlers = [
      # x.com always → Personal, even when clicked from Slack. Must come first
      # (handlers are first-match-wins) so it beats the Slack rule below.
      {
        match = [
          "x.com/*"
          "*.x.com/*"
        ];
        browser = "Google Chrome";
        profile = "Personal";
      }
      # Every link clicked inside the Slack app → Telepatia (work).
      {
        fromApp = "com.tinyspeck.slackmacgap";
        browser = "Google Chrome";
        profile = "Telepatia";
      }
      # Work GitHub org → Telepatia.
      {
        match = [ "github.com/telepatia-ai/*" ];
        browser = "Google Chrome";
        profile = "Telepatia";
      }
    ];
  };

  # Terminal
  ghostty.enable = true;

  # Chat & communication
  slack.enable = true;
  teams.enable = true;
  telegram.enable = true;
  whatsapp.enable = true;
  discord.enable = true;

  # Media
  iina.enable = true;
  spotify.enable = true;
  stremio.enable = true;
  affinity.enable = true;

  # Productivity
  anki.enable = true;
  anytype.enable = true;
  calibre.enable = true;
  obsidian.enable = true;
  zotero.enable = true;
  "notion-calendar".enable = true;
  loom.enable = true;
  netnewswire.enable = true;
  sparkmail.enable = true;
  figma.enable = true;
  libreoffice.enable = true;
  word.enable = true;
  "windows-app".enable = true;
  granola.enable = true;
  "cold-turkey-blocker".enable = true;
  selfcontrol.enable = true;

  # Networking
  tailscale.enable = true;
  "cloudflare-warp".enable = true;
  wireguard.enable = true;

  # Security
  "1password".enable = true;
  yubikey.enable = true;

  # Darwin utilities
  "alt-tab".enable = true;
  hammerspoon.enable = true;
  keyboardcleantool.enable = true;
  "scroll-reverser".enable = true;
  raycast.enable = true;
  openlogi.enable = true;

  # Finance
  paisa.enable = true;
  ledger.enable = true;

  # Games
  sony.enable = true;
  prismlauncher.enable = true;
  steam.enable = true;
}
