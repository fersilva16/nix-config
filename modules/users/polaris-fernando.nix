# polaris user composition — first wave is CLI + dev + desktop sessions
# (plan Phase 1; GUI app parity grows on demand in Phase 4).
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

  # Security
  "1password".enable = true;

  # Desktop sessions
  keyd.enable = true;
  feh.enable = true;
  flameshot.enable = true;
  niri.enable = true;
  noctalia.enable = true;
}
