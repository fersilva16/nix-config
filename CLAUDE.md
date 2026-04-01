# CLAUDE.md

## What is this repo?

A nix-darwin flake configuration for a single macOS Apple Silicon host (`m1`), managing system settings, packages, and dotfiles for user `fernando`. It uses nix-darwin for system-level config and home-manager for user-level config, with declarative Homebrew for GUI apps not in nixpkgs.

## Commands

- **Rebuild:** `sudo darwin-rebuild switch --flake .#m1`
- **Format:** `nixfmt <file.nix>` (RFC style, enforced by pre-commit)
- **Lint:** `statix check .` — **run after every edit to .nix files, before rebuild**
- **Shell lint:** `shellcheck <file.sh>`
- **Enter dev shell:** `nix develop` (auto-activates via direnv)

## Architecture

```
flake.nix                    # Entry point: inputs + outputs
lib/mkDarwinHost.nix         # Factory: creates a nix-darwin system config
lib/mkUserModule.nix         # Factory: creates a capability module with enable option
lib/forPlatform.nix          # Utility: platform-aware value selector (darwin/linux)
modules/hosts/m1.nix         # Host definition: system-level + mkUserModule imports
modules/users/m1-fernando.nix # User composition: structural config + enable flags
modules/<category>/<app>.nix # Individual app/tool modules
overlay/                     # Custom packages (paisa, flexoki-tmux, tmux-extras)
```

### Module patterns

#### `mkUserModule` (preferred — new modules should use this)

`mkUserModule` creates a self-contained capability module. It declares an option under `modules.users.<user>.<name>`, applies system config once when any user enables it, and applies home config per-user. Modules using this pattern are imported at the **host level** (`modules/hosts/m1.nix`) and users opt in via enable flags.

```nix
# Simple — HM-only (modules/cli/bat.nix, imported in m1.nix):
{ mkUserModule, ... }:
mkUserModule {
  name = "bat";
  home.programs.bat.enable = true;
}

# System-only cask:
{ mkUserModule, ... }:
mkUserModule {
  name = "slack";
  system.homebrew.casks = [ "slack" ];
}

# Unified system + user:
{ mkUserModule, pkgs, ... }:
mkUserModule {
  name = "fish";
  system = {
    environment.systemPackages = [ pkgs.fish ];
    programs.fish.enable = true;
  };
  home.programs.fish = {
    enable = true;
    shellAliases = { ll = "eza -la"; };
  };
}
```

Fields:

- **`name`** — Module name. Creates `modules.users.<user>.<name>.enable`.
- **`system`** — (optional) System-level config, applied once when any user enables it.
- **`home`** — (optional) Per-user home-manager config. Can be a static attrset or a function `{ cfg, username, userCfg } -> attrset` when per-user option values or cross-module checks are needed. `userCfg` is the full `modules.users.<user>` config for that user — use it for `mkIf` guards on outbound integrations (see below).
- **`extraOptions`** — (optional) Custom per-user options (attrset of `mkOption` defs). Accessed via `cfg` in the `home` function.
- **`requires`** — (optional) List of module names to auto-enable for every user who enables this module. Only sets `enable = true` (with `mkDefault`, so explicit `enable = false` overrides). See "requires vs mkIf" below for when to use this vs conditional integration.

```nix
# extraOptions + requires:
{ mkUserModule, lib, ... }:
mkUserModule {
  name = "1password";
  requires = [ "git" ];
  extraOptions.sshAgent = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Whether to use 1Password SSH agent.";
  };
  system.homebrew.casks = [ "1password" ];
  home = { cfg, userCfg, ... }: {
    programs.ssh.extraConfig = lib.mkIf cfg.sshAgent ''
      IdentityAgent "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
    '';
    # Outbound integration: configure git signing when git is also enabled
    programs.git.settings = lib.mkIf userCfg.git.enable {
      gpg.format = "ssh";
      commit.gpgsign = true;
    };
  };
}
```

User composition (in user file):

```nix
modules.users.fernando = {
  bat.enable = true;
  "1password" = { enable = true; sshAgent = false; };
};
```

### `forPlatform` utility

`forPlatform` selects a value based on the current system platform. Available via `specialArgs` in all modules. When only one platform is specified, the other side's identity value is inferred from the type (`""` for strings, `[]` for lists, `{}` for attrsets).

```nix
# Both platforms:
forPlatform { darwin = "/Users/${u}"; linux = "/home/${u}"; }

# Single platform — other side inferred:
forPlatform { darwin = [ pkgs.iterm2 ]; }  # linux → []

# Composable — strings via interpolation, lists via ++, attrsets via mkMerge:
home.packages = [ sharedPkg ] ++ forPlatform { darwin = [ pkgs.iterm2 ]; };
```

### Where things go

- **System-level modules** (fonts, nix settings, macOS defaults, Touch ID): imported directly in `modules/hosts/m1.nix`
- **User-level modules** (packages, programs, dotfiles, homebrew casks): imported via `modules/users/m1-fernando.nix`
- **Custom packages/derivations**: `overlay/pkgs/` with registration in `overlay/pkgs/pkgs.nix`
- **Shell scripts** (tmux utilities, ledger sync): bundled as custom packages in the overlay

### Adding a new app

1. Create `modules/<category>/<app>.nix` using `mkUserModule`
2. Import it in `modules/hosts/m1.nix`
3. Add `<name>.enable = true;` to `modules.users.fernando` in the user file
4. Run `sudo darwin-rebuild switch --flake .#m1` to apply

### Homebrew behavior

Homebrew is declarative with `onActivation.cleanup = "zap"` -- any cask not declared in Nix modules will be **removed** on rebuild. Always add casks via module files, never `brew install` manually.

## Module mental model

### Modules are capabilities, not config fragments

A module is a self-contained definition of a capability — not "some config that needs a username" or "an attrset that sets HM options." It declares what it offers (options), what the system needs to support it (system config), and what each user gets when they enable it (home config). All three concerns live in one place because they describe one thing.

Users declare intent (`bat.enable = true`), modules own all the plumbing. The user never writes `home-manager.users.fernando.programs.bat.enable = true` — they say "I want bat" and the module figures out what that means at every layer.

### User → System, not System → User

The direction is always bottom-up: a user asks for a capability, the module handles system-wide dependencies as a side effect. If two users both enable fish, the module adds `pkgs.fish` to `environment.systemPackages` twice — Nix deduplicates. Nobody coordinates. The system-level setup is a consequence of user intent, never the other way around.

### Multi-user and multi-system are properties, not features

They fall out of the model. If modules are capabilities and users declare intent, multiple users work because Nix merges. Multiple systems work because hosts compose different capability sets. Don't "add multi-user support" — if you need to, the abstraction is wrong.

### Each module owns its outbound integrations

A module that introduces a capability is responsible for integrating with other modules — not the other way around. The module that "knows how" owns the glue.

The principle: if tool A enhances tool B, the A module reaches into B's config. The B module stays pure — it doesn't know A exists.

- **1password** knows how SSH signing works → it configures `git` signing when the user also has `git` enabled
- **bat** knows it replaces `cat` → it adds the fish alias when the user also has `fish` enabled
- **git** owns its fish aliases/functions → it sets them when the user also has `fish` enabled
- **eza** owns the `ls` alias → it sets it when the user also has `fish` enabled

This means: if you add a new tool that enhances an existing one, the NEW module reaches into the existing module's config. The existing module never changes.

Outbound integrations use `mkIf userCfg.<module>.enable` to guard the cross-module config:

```nix
{ mkUserModule, lib, ... }:
mkUserModule {
  name = "eza";
  home = { userCfg, ... }: {
    programs.eza.enable = true;
    # Only set fish alias when fish is also enabled for this user
    programs.fish.shellAliases = lib.mkIf userCfg.fish.enable {
      ls = "eza -lag";
    };
  };
}
```

### `requires` vs `mkIf` — when to use which

Both handle cross-module relationships, but they serve different purposes:

- **`requires`** = "enabling X auto-enables Y" — a hard dependency where X is fundamentally useless without Y.
- **`mkIf userCfg.Y.enable`** = "only apply this config when Y is also enabled" — a soft integration where X works standalone but enhances Y when present.

The test: **is the module fundamentally useless without the other?**

| Relationship | Mechanism | Why |
|---|---|---|
| lazygit → git | `requires` | Lazygit IS a git UI — useless without git |
| 1password → git | `requires` | Module's purpose is git SSH signing — useless without git |
| git → fish | `mkIf` | Git works without fish; aliases are a bonus |
| eza → fish | `mkIf` | Eza works without fish; the `ls` alias is a bonus |
| bat → fish | `mkIf` | Bat works without fish; the `cat` alias is a bonus |
| starship → fish | `mkIf` | Starship works with any shell; fish prompt hook is a bonus |

**Rule of thumb:** if removing the dependency means the module still installs and does something useful, use `mkIf`. If it becomes an empty shell that installs a binary nobody can use, use `requires`.

### Nix is lazy — so modules can be fearless

Disabled config paths (`mkIf false`) are never evaluated and cost nothing. Modules can freely declare options, reference each other, and conditionally integrate — without import ordering, explicit dependency graphs, or worrying about what else is loaded. The module system collects everything, merges it, and only evaluates what's needed. This is what makes self-contained capability modules possible: they don't need to know who else is in the system.

## Code style

- 2-space indentation, UTF-8, LF line endings
- Format with `nixfmt` (nixfmt-rfc-style)
- Lint with `statix`
- Shell scripts linted with `shellcheck`
- Pre-commit hooks enforce all of the above automatically

## Commit conventions

Conventional commits with scope: `feat(<scope>): description`, `fix(<scope>): description`, `chore(<scope>): description`. Scope is typically the module category or app name (e.g., `tmux`, `nvim`, `m1`, `hammerspoon`, `git`).
