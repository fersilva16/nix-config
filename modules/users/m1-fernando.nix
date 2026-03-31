{
  pkgs,
  inputs,
  config,
  ...
}:
let
  username = "fernando";
  homeDirectory = "/Users/${username}";

  inherit (inputs)
    homebrew-core
    homebrew-cask
    homebrew-bundle
    homebrew-schpet-tap
    ;
in
{
  # ── User account ──────────────────────────────────────────────────────
  users.users.${username} = {
    shell = pkgs.fish;
    home = homeDirectory;
  };

  system.primaryUser = username;

  # ── Home Manager bootstrap ───────────────────────────────────────────
  home-manager.users.${username}.home = {
    inherit homeDirectory username;
    stateVersion = "25.05";
  };

  # ── Homebrew (declarative, cleanup = zap) ────────────────────────────
  nix-homebrew = {
    enable = true;
    enableRosetta = true;
    user = username;

    taps = {
      "homebrew/homebrew-core" = homebrew-core;
      "homebrew/homebrew-cask" = homebrew-cask;
      "homebrew/homebrew-bundle" = homebrew-bundle;
      "schpet/homebrew-tap" = homebrew-schpet-tap;
    };

    mutableTaps = false;
  };

  homebrew = {
    enable = true;
    onActivation.cleanup = "zap";
    taps = builtins.attrNames config.nix-homebrew.taps;
  };

  # ── User capabilities ───────────────────────────────────────────────
  modules.users.${username} = {
    # Shell & CLI
    bat.enable = true;
    ssh.enable = true;
    fish.enable = true;
    starship.enable = true;
    direnv.enable = true;
    tmux.enable = true;
    zoxide.enable = true;
    eza.enable = true;
    fzf.enable = true;
    ripgrep.enable = true;

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
    opencode.enable = true;
    rtk.enable = true;
    ollama.enable = true;
    linear.enable = true;

    # Editors
    nvim.enable = true;
    vscode.enable = true;
    cursor.enable = true;
    intellij.enable = true;
    "android-studio".enable = true;

    # Browsers
    firefox.enable = true;
    chrome.enable = true;

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
  };
}
