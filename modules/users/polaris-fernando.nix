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
    authorizedKeys = import ../../keys/fernando.nix;
  };
  fish.enable = true;
  starship.enable = true;
  direnv.enable = true;
  zoxide.enable = true;
  eza.enable = true;
  fzf.enable = true;
  gum.enable = true;
  fd.enable = true;
  ripgrep.enable = true;
  fastfetch.enable = true;
  todoist.enable = true;

  # Dev tools
  git.enable = true;
  lazygit.enable = true;
  incus.enable = true;
  claude.enable = true;
  "claude-code".enable = true;
  # Nalum (this host's omo), the mux as `tmux`, and the wt and Todoist tools.
  limi-suite.enable = true;
  agent-path.enable = true;
  i-have-adhd.enable = true;
  ponytail.enable = true;
  autoresearch.enable = true;
  show-me.enable = true;
  ship.enable = true;
  unsupervised.enable = true;
  ollama = {
    enable = true;
    models = [
      "gpt-oss:20b" # agents: reliable tool calling
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
  steam.enable = true;

  # Networking
  tailscale.enable = true;
  # Receives vega's keyboard + mouse; with the receiver (Easy-Switch 2) in
  # use, the pointer crosses back to vega the same way. vega's address and
  # fingerprint come from what vega advertises (modules/system/fleet.nix).
  "lan-mouse" = {
    enable = true;
    # polaris's own ~/.config/lan-mouse/lan-mouse.pem, advertised to vega.
    fingerprint = "5a:07:ca:06:ca:66:8e:04:e1:65:02:43:7a:e7:63:e1:4c:e7:02:96:04:e9:58:f3:b0:37:3e:b5:92:37:87:3e";
    peers.vega = "right";
  };

  # Security
  "1password".enable = true;
  yubikey = {
    enable = true;
    # Touch-to-authenticate (sudo, lock screen). `pamu2fcfg` on polaris.
    u2fKeys = [
      "uPIFzVCaaqHhUL3MfvUcihgs/qp9KuA8uq/5ujm/sYJLj0G1ISpFvHVIAxM6SebbF2fNUpDkSv3k3nL+nEJDCg==,0WQqbztd1fklkvGHIE9W7i1SqpFccbgJvD4RUetcswX7YAXlSnT7nHS5I9vDpick43KW3jDF89M0ckZO4WSJhg==,es256,+presence"
    ];
  };

  # Desktop sessions
  xremap.enable = true;
  feh.enable = true;
  niri.enable = true;
  noctalia.enable = true;
  vicinae.enable = true;
  nautilus.enable = true;
  gtk.enable = true;
  qt.enable = true;
  xdg-user-dirs.enable = true;
}
