{ mkUser, ... }:
mkUser {
  name = "fernando";

  # Shell & CLI
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
  linear.enable = true;

  # Editors
  nvim.enable = true;
  vscode.enable = true;
  cursor.enable = true;
  intellij.enable = true;
  "android-studio".enable = true;

  # Browsers
  firefox = {
    enable = true;
    profileApps = {
      enable = true;
      profiles = {
        personal = {
          displayName = "Firefox Personal";
          profileDir = "pmbNxl3q.Profile 1";
        };
        telepatia = {
          displayName = "Firefox Telepatia";
          profileDir = "xpo8mNTY.Profile 2";
        };
      };
    };
  };
  chrome.enable = true;

  # URL router — set Finicky as the default browser so links from Slack/email/etc
  # route to the right Firefox profile instead of piling into one.
  finicky = {
    enable = true;
    hideIcon = true;
    defaultBrowser = "/Applications/Firefox Personal.app";
    handlers = [
      # x.com always → Personal, even when clicked from Slack. Must come first
      # (handlers are first-match-wins) so it beats the Slack rule below.
      {
        match = [
          "x.com/*"
          "*.x.com/*"
        ];
        browser = "/Applications/Firefox Personal.app";
      }
      # Every link clicked inside the Slack app → Telepatia (work).
      {
        fromApp = "com.tinyspeck.slackmacgap";
        browser = "/Applications/Firefox Telepatia.app";
      }
      # Work GitHub org → Telepatia.
      {
        match = [ "github.com/telepatia-ai/*" ];
        browser = "/Applications/Firefox Telepatia.app";
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

  # Productivity
  anki.enable = true;
  anytype.enable = true;
  calibre.enable = true;
  obsidian.enable = true;
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
  hammerspoon.enable = true;
  keyboardcleantool.enable = true;
  raycast.enable = true;

  # Finance
  paisa.enable = true;
  ledger.enable = true;

  # Games
  sony.enable = true;
  prismlauncher.enable = true;
  steam.enable = true;
}
