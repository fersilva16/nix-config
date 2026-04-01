_: {
  networking.hostName = "m1";
  system.primaryUser = "fernando";

  imports = [
    ../users/m1-fernando.nix

    # System modules (not mkUserModule — applied unconditionally)
    ../system/user-bootstrap.nix
    ../system/homebrew.nix
    ../darwin/darwin-default.nix
    ../darwin/sudo-touchid.nix
    ../darwin/watcher.nix
    ../fonts/caskaydia-cove.nix
    ../system/nix.nix
    ../system/pkg-config.nix
    ../system/sshd.nix
    ../cli/wget.nix
    ../cli/unrar.nix

    # User modules (mkUserModule pattern — enabled per-user via modules.users.<name>)

    # Shell & CLI
    ../cli/bat.nix
    ../cli/ssh.nix
    ../cli/fish.nix
    ../cli/starship.nix
    ../cli/direnv.nix
    ../cli/tmux.nix
    ../cli/zoxide.nix
    ../cli/eza.nix
    ../cli/fzf.nix
    ../cli/ripgrep.nix
    ../cli/chrome-cli.nix
    ../cli/readwise.nix

    # Dev tools
    ../dev/git.nix
    ../dev/lazygit.nix
    ../dev/awscli.nix
    ../dev/flyctl.nix
    ../dev/mongosh.nix
    ../dev/stern.nix
    ../dev/dbeaver.nix
    ../dev/studio-3t.nix
    ../dev/postman.nix
    ../dev/ngrok.nix
    ../dev/orbstack.nix
    ../dev/java-25.nix
    ../dev/minikube.nix
    ../dev/doppler.nix
    ../dev/claude.nix
    ../dev/claude-code.nix
    ../dev/opencode.nix
    ../dev/rtk.nix
    ../dev/ollama.nix
    ../dev/linear.nix

    # Editors
    ../editor/nvim.nix
    ../editor/vscode/vscode.nix
    ../editor/cursor.nix
    ../editor/intellij.nix
    ../editor/android-studio.nix

    # Browsers
    ../browser/firefox.nix
    ../browser/chrome.nix

    # Terminal
    ../terminal/ghostty.nix

    # Chat & communication
    ../chat/slack.nix
    ../chat/teams.nix
    ../chat/telegram.nix
    ../chat/whatsapp.nix
    ../chat/discord.nix

    # Media
    ../media/iina.nix
    ../media/spotify.nix
    ../media/stremio.nix

    # Productivity
    ../productivity/anki.nix
    ../productivity/anytype.nix
    ../productivity/calibre.nix
    ../productivity/obsidian.nix
    ../productivity/notion-calendar.nix
    ../productivity/loom.nix
    ../productivity/netnewswire.nix
    ../productivity/sparkmail.nix
    ../productivity/figma.nix
    ../productivity/libreoffice.nix
    ../productivity/word.nix
    ../productivity/windows-app.nix
    ../productivity/granola.nix
    ../productivity/cold-turkey-blocker.nix
    ../productivity/selfcontrol.nix

    # Networking
    ../networking/tailscale.nix
    ../networking/cloudflare-warp.nix
    ../networking/wireguard.nix

    # Security
    ../security/1password.nix
    ../security/yubikey.nix

    # Darwin utilities
    ../darwin/hammerspoon/hammerspoon.nix
    ../darwin/keyboardcleantool.nix
    ../darwin/raycast.nix

    # Finance
    ../ledger/paisa.nix
    ../ledger/ledger.nix

    # Games
    ../games/sony.nix
    ../games/prismlauncher.nix
    ../games/steam.nix
  ];
}
