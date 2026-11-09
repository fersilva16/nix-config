# altair user composition — headless server: shell, editor, remote access,
# and the network services it hosts.
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
  fd.enable = true;
  realdu.enable = true;
  ripgrep.enable = true;

  # Dev tools
  git.enable = true;
  # Limi's hub: calendar, mail, feeds and the personal Nalum, for the fleet.
  limi-hub.enable = true;

  # Editors
  nvim.enable = true;

  # Networking
  tailscale.enable = true;
  adguardhome.enable = true;

  # Monitoring
  metrics.enable = true;
}
