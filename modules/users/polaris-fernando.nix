# polaris user composition — first wave is CLI + dev + desktop sessions
# (plan Phase 1; GUI app parity grows on demand in Phase 4).
{ mkUser, ... }:
mkUser {
  name = "fernando";

  # Shell & CLI
  atuin.enable = true;
  bat.enable = true;
  ssh = {
    enable = true;
    # 1Password "SSH Key" — the auth key, distinct from the "SSH Signing Key"
    # that modules/security/1password.nix hands to git.
    authorizedKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBBF9AdnNjLReo7Z2U0gifKkH3FR4str9pMvBbAcCzaj"
    ];
  };
  fish.enable = true;
  starship.enable = true;
  direnv.enable = true;
  tmux.enable = true;
  worktree.enable = true;
  zoxide.enable = true;
  eza.enable = true;
  fzf.enable = true;
  gum.enable = true;
  fd.enable = true;
  ripgrep.enable = true;
  # No panel: it is drawn by hammerspoon, which is darwin-only.
  todoist.enable = true;

  # Dev tools
  git.enable = true;
  lazygit.enable = true;
  opencode.enable = true;
  "claude-code".enable = true;
  omo.enable = true;
  agent-path.enable = true;
  i-have-adhd.enable = true;
  ponytail.enable = true;
  autoresearch.enable = true;
  show-me.enable = true;
  ship.enable = true;
  opencode-manager.enable = true;
  ollama = {
    enable = true;
    models = [
      "gpt-oss:20b" # agents/opencode: reliable tool calling
      "gemma4:26b-a4b-qat" # general: smartest fit for 16 GB, 4B-active MoE
    ];
  };

  # Editors
  nvim.enable = true;
  vscode.enable = true;

  # Browsers
  firefox.enable = true;
  chrome.enable = true;

  # Terminal
  ghostty.enable = true;

  # Chat
  discord.enable = true;

  # Games
  heroic.enable = true; # Rocket League (Epic)

  # Networking
  tailscale.enable = true;
  # Receives vega's keyboard + mouse; with the receiver (Easy-Switch 2) in
  # use, the pointer crosses back to vega the same way. Fingerprint: vega's
  # ~/.config/lan-mouse/lan-mouse.pem (see modules/productivity/lan-mouse.nix).
  "lan-mouse" = {
    enable = true;
    settings = {
      authorized_fingerprints."e5:65:3f:47:86:06:94:45:8b:c2:aa:1e:91:3e:4a:6c:17:e8:62:36:53:96:0a:8e:bd:53:41:b6:52:ed:4f:05" =
        "vega";
      clients = [
        {
          position = "right";
          hostname = "vega.local";
          activate_on_startup = true;
        }
      ];
    };
  };

  # Security
  "1password".enable = true;

  # Desktop sessions
  xremap.enable = true;
  feh.enable = true;
  flameshot.enable = true;
  niri.enable = true;
  noctalia.enable = true;
  vicinae.enable = true;
}
