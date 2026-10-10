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
  tmux = {
    enable = true;
    # "polaris ⇢" in the session picker hops this terminal into polaris's
    # tmux (no nesting); prefix+d there comes back. Nothing connects until
    # it is picked.
    #
    # The hop also opens a SOCKS5 proxy on 127.0.0.1:1080 that egresses from
    # polaris, alive while you are over there. That is a convenience (a route
    # out through the house), NOT the way this machine reaches the tailnet —
    # reaching polaris is the precondition for the proxy, so it cannot also
    # be the means. Point clients at it with `--socks5-hostname` (curl) or
    # ProxyCommand (ssh) so names resolve on the polaris side. It is a full
    # proxy, not a tailnet-only route: anything aimed at 1080 leaves via the
    # house rather than via WARP.
    peers.polaris = [
      "-D"
      "1080"
    ];
  };
  worktree.enable = true;
  zoxide.enable = true;
  eza.enable = true;
  fzf.enable = true;
  gum.enable = true;
  fd.enable = true;
  ripgrep.enable = true;
  chrome-cli.enable = true;
  readwise.enable = true;
  todoist = {
    enable = true;
    panel.enable = true;
  };

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
  tart.enable = true;
  "java-25".enable = true;
  minikube.enable = true;
  doppler.enable = true;
  claude.enable = true;
  "claude-code".enable = true;
  codex.enable = true;
  opencode.enable = false;
  omo.enable = true;
  i-have-adhd.enable = true;
  ponytail.enable = true;
  autoresearch.enable = true;
  show-me.enable = true;
  ship.enable = true;
  unsupervised.enable = true;
  agent-path.enable = true;
  openclaw.enable = true;
  playwright-cli.enable = true;
  opencode-manager.enable = true;
  # rtk.enable = true;
  ollama.enable = true;
  anonymize.enable = true;
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
  slack = {
    enable = true;
    later.workspace = "telepatiaworkspace.slack.com";
    later.enable = true;
  };
  teams.enable = true;
  telegram.enable = true;
  whatsapp.enable = true;
  discord.enable = true;

  # Media
  iina.enable = true;
  obs.enable = true;
  "screen-studio".enable = true;
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
  anydesk.enable = true;
  granola.enable = true;
  "wispr-flow".enable = true;
  "cold-turkey-blocker".enable = false;
  selfcontrol.enable = true;

  # Networking
  tailscale.enable = true;
  "cloudflare-warp".enable = true;
  wireguard.enable = true;
  openfortivpn.enable = true;

  # One keyboard + mouse (Bluetooth to vega) also drives polaris: the pointer
  # crosses at the screen edge. polaris's address and fingerprint come from
  # what polaris advertises (modules/system/fleet.nix).
  "lan-mouse" = {
    enable = true;
    # vega's own ~/.config/lan-mouse/lan-mouse.pem, advertised to polaris.
    fingerprint = "e5:65:3f:47:86:06:94:45:8b:c2:aa:1e:91:3e:4a:6c:17:e8:62:36:53:96:0a:8e:bd:53:41:b6:52:ed:4f:05";
    # On demand: vega is the sending side, so nothing crosses until it runs.
    # polaris keeps listening.
    autoStart = false;
    peers.polaris = "left";
  };

  # Security
  "1password".enable = true;
  yubikey.enable = true;

  # Darwin utilities
  "alt-tab".enable = true;
  hammerspoon.enable = true;
  keyboardcleantool.enable = true;
  "scroll-reverser".enable = true;
  raycast.enable = true;
  vicinae.enable = true;
  openlogi.enable = true;

  # Finance
  paisa.enable = true;
  ledger.enable = true;

  # Games
  sony.enable = true;
  prismlauncher.enable = true;
  steam.enable = true;
}
