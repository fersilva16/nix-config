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
  zoxide.enable = true;
  eza.enable = true;
  fzf.enable = true;
  fd.enable = true;
  ripgrep.enable = true;

  # Dev tools
  git.enable = true;
  lazygit.enable = true;
  opencode = {
    enable = true;
    server.enable = false;
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

  # Networking
  tailscale.enable = true;

  # Security
  "1password".enable = true;

  # Desktop sessions
  keyd.enable = true;
  feh.enable = true;
  flameshot.enable = true;
  niri.enable = true;
  noctalia.enable = true;
}
