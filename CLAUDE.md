# CLAUDE.md

## What is this repo?

A nix-darwin flake configuration for a single macOS Apple Silicon host (`m1`), managing system settings, packages, and dotfiles for user `fernando`. It uses nix-darwin for system-level config and home-manager for user-level config, with declarative Homebrew for GUI apps not in nixpkgs.

## Commands

- **Rebuild:** `sudo darwin-rebuild switch --flake .#m1`
- **Format:** `nixfmt <file.nix>` (RFC style, enforced by pre-commit)
- **Lint:** `statix check .`
- **Shell lint:** `shellcheck <file.sh>`
- **Enter dev shell:** `nix develop` (auto-activates via direnv)

## Architecture

```
flake.nix                    # Entry point: inputs + outputs
lib/mkDarwinHost.nix         # Factory: creates a nix-darwin system config
lib/mkUserImports.nix        # Factory: threads username through module imports
modules/hosts/m1.nix         # Host definition: system-level imports
modules/users/m1-fernando.nix # User composition: ~70 module imports
modules/<category>/<app>.nix # Individual app/tool modules
overlay/                     # Custom packages (paisa, flexoki-tmux, tmux-extras)
```

### Module patterns

There are two module patterns depending on what the module configures:

**Homebrew cask wrapper** (GUI apps not in nixpkgs) -- uses `_:` since no args needed:

```nix
_: {
  homebrew.casks = [ "slack" ];
}
```

**Nix package or home-manager config** -- receives `username` and sets user-scoped attributes:

```nix
{ username, pkgs, ... }:
{
  home-manager.users.${username} = {
    home.packages = with pkgs; [ claude-code ];
  };
}
```

Modules that need more args (e.g., `inputs`, `config`, `lib`) destructure them as needed. The `username` argument is threaded through by `lib/mkUserImports.nix`.

### Where things go

- **System-level modules** (fonts, nix settings, macOS defaults, Touch ID): imported directly in `modules/hosts/m1.nix`
- **User-level modules** (packages, programs, dotfiles, homebrew casks): imported via `modules/users/m1-fernando.nix`
- **Custom packages/derivations**: `overlay/pkgs/` with registration in `overlay/pkgs/pkgs.nix`
- **Shell scripts** (tmux utilities, ledger sync): bundled as custom packages in the overlay

### Adding a new app

1. Create `modules/<category>/<app>.nix` using the appropriate pattern above
2. Import it in `modules/users/m1-fernando.nix` (user-level) or `modules/hosts/m1.nix` (system-level)
3. Run `sudo darwin-rebuild switch --flake .#m1` to apply

### Homebrew behavior

Homebrew is declarative with `onActivation.cleanup = "zap"` -- any cask not declared in Nix modules will be **removed** on rebuild. Always add casks via module files, never `brew install` manually.

## Code style

- 2-space indentation, UTF-8, LF line endings
- Format with `nixfmt` (nixfmt-rfc-style)
- Lint with `statix`
- Shell scripts linted with `shellcheck`
- Pre-commit hooks enforce all of the above automatically

## Commit conventions

Conventional commits with scope: `feat(<scope>): description`, `fix(<scope>): description`, `chore(<scope>): description`. Scope is typically the module category or app name (e.g., `tmux`, `nvim`, `m1`, `hammerspoon`, `git`).
