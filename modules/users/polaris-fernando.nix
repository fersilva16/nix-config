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
  # TODO(post-boot): re-enable — the custom patches force a full local
  # source rebuild, too heavy for install day.
  opencode = {
    enable = false;
    server.enable = false;
  };

  # Editors
  nvim.enable = true;

  # Browsers
  firefox.enable = true;
  chrome.enable = true;

  # Terminal
  ghostty.enable = true;

  # Security
  "1password".enable = true;

  # Desktop sessions
  feh.enable = true;
  flameshot.enable = true;
  hyprland.enable = true;
  i3.enable = true;
}
