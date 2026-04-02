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
lib/mkDarwinHost.nix         # Factory: creates a nix-darwin system from structured declaration
lib/mkUserModule.nix         # Factory: creates a capability module with enable option
lib/mkUser.nix               # Factory: creates { name, module } for user bootstrapping + enable flags
lib/forPlatform.nix          # Utility: platform-aware value selector (darwin/linux)
modules/hosts/m1.nix         # Host definition: mkDarwinHost call with host-specific config
modules/users/m1-fernando.nix # User composition: mkUser with enable flags
modules/<category>/<app>.nix # Individual app/tool modules
modules/<category>/<app>/    # Module with parts (<app>.nix + part files)
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

# System + user:
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

- **`name`** — Creates `modules.users.<user>.<name>.enable`.
- **`system`** — (optional) System-level config, applied once when any user enables it.
- **`home`** — (optional) Per-user HM config. Static attrset or function `{ cfg, username, userCfg } -> attrset`. `userCfg` is the full `modules.users.<user>` config — use for `mkIf` guards on outbound integrations.
- **`extraOptions`** — (optional) Custom per-user options (`mkOption` defs). Accessed via `cfg` in `home`.
- **`requires`** — (optional) Auto-enable listed modules (`mkDefault`, overridable). See `requires` vs `mkIf` below.

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

#### `parts` — splitting modules into sub-features

When a module bundles distinct concerns (e.g., a CLI tool + a background server), use `parts` to split into separate files with independent enable toggles. Each part creates a nested option: `modules.users.<user>.<name>.<partName>.enable`.

Parts are plain attrsets with the same fields as `mkUserModule` (`system`, `home`, `extraOptions`), plus `default` (bool, defaults to `true`). The parent passes shared bindings via import args.

```nix
# modules/dev/opencode/opencode.nix — parent owns the binary + settings
{ mkUserModule, pkgs, lib, ... }:
mkUserModule {
  name = "opencode";
  parts = {
    server = import ./server.nix { inherit pkgs opencode-unwrapped serverPort; };
  };
  home = {
    programs.opencode = {
      enable = true;
      package = lib.mkDefault opencode-unwrapped;  # part overrides when enabled
      settings = { ... };
    };
  };
}

# modules/dev/opencode/server.nix — part owns the daemon + wrapper
{ pkgs, opencode-unwrapped, serverPort }:
{
  system.launchd.user.agents.opencode-server = { ... };
  home.programs.opencode.package = opencode-wrapper;  # wins over mkDefault
}
```

Part `home` can be a function `{ cfg, parentCfg, username, userCfg } -> attrset`. `cfg` is the part's config; `parentCfg` is the parent's.

**Priority trick:** parent sets `lib.mkDefault unwrapped`, part sets `wrapper` at normal priority. Part enabled → wrapper wins. Part disabled → parent's default applies.

| Situation | Use |
|---|---|
| Sub-feature is useless without parent | `parts` |
| Sub-feature is genuinely independent | Separate `mkUserModule` |

### `forPlatform` utility

Available via `specialArgs`. When only one platform is specified, the other defaults to the identity value for that type.

```nix
forPlatform { darwin = "/Users/${u}"; linux = "/home/${u}"; }
forPlatform { darwin = [ pkgs.iterm2 ]; }  # linux → []
home.packages = [ sharedPkg ] ++ forPlatform { darwin = [ pkgs.iterm2 ]; };
```

### `mkDarwinHost` — host declaration

`mkDarwinHost` creates a nix-darwin system from a structured declaration. It absorbs all system plumbing (module discovery, `specialArgs`, home-manager/nix-homebrew wiring, nixpkgs config) so host files stay declarative. Field names are platform-agnostic to support a future `mkNixOSHost`.

```nix
# modules/hosts/m1.nix
{ mkDarwinHost }:
let
  fernando = import ../users/m1-fernando.nix;
in
mkDarwinHost {
  hostName = "m1";
  primaryUser = fernando;
  users = [ fernando ];
}

# flake.nix
m1 = import ./modules/hosts/m1.nix { inherit mkDarwinHost; };
```

Fields:

- **`hostName`** — (required) Network hostname.
- **`primaryUser`** — (required) Primary user of the host. Accepts a user function (imported `mkUser` file) — the username is extracted automatically from `mkUser`'s `{ name, module }` return. Also accepts a plain string.
- **`system`** — (optional, default `"aarch64-darwin"`) Nix system identifier.
- **`stateVersion`** — (optional, default `5`) nix-darwin state version.
- **`users`** — (optional, default `[]`) List of user functions (imported `mkUser` files). Each is unwrapped via `{ name, module }` to feed `.module` to the module system.
- **`extraModules`** — (optional, default `[]`) Escape hatch for additional modules.

What it handles automatically:

- Module auto-discovery (all `modules/<category>/` modules)
- `specialArgs` (factories: `mkUserModule`, `mkUser`, `mkSystemModule`; utilities: `forPlatform`)
- home-manager and nix-homebrew darwin module wiring
- nixpkgs overlays and `allowUnfree`

### `mkUser` — user composition

`mkUser` creates a user module that bootstraps the system account, home-manager home, and module enable flags. Available via `specialArgs`. User files use it instead of writing raw `modules.users` config.

Returns `{ name, module }` so host factories (`mkDarwinHost`, future `mkNixOSHost`) can extract the username without duplication.

```nix
# modules/users/m1-fernando.nix
{ mkUser, ... }:
mkUser {
  name = "fernando";
  bat.enable = true;
  git.enable = true;
  opencode = { enable = true; server.enable = false; };
}
```

Fields:

- **`name`** — (required) Username. Creates `users.users.<name>`, `home-manager.users.<name>`, and `modules.users.<name>`.
- **`stateVersion`** — (optional, default `"25.11"`) home-manager state version.
- **Everything else** — Passed directly to `modules.users.<name>` as module enable flags and options.

What it handles automatically:

- `users.users.<name>.home` — platform-aware via `forPlatform`
- `home-manager.users.<name>.home.{username, homeDirectory, stateVersion}`

### Adding a new app

Create `modules/<category>/<app>.nix` using `mkUserModule` → add `<name>.enable = true` in the user file (`mkUser` call) → rebuild. Module discovery is automatic — no need to import in the host file.

### Homebrew behavior

Homebrew is declarative with `onActivation.cleanup = "zap"` -- any cask not declared in Nix modules will be **removed** on rebuild. Always add casks via module files, never `brew install` manually.

## Module mental model

### Modules are capabilities, not config fragments

A module is a self-contained definition of a capability — not "some config that needs a username" or "an attrset that sets HM options." It declares what it offers (options), what the system needs to support it (system config), and what each user gets when they enable it (home config). All three concerns live in one place because they describe one thing.

Users declare intent (`bat.enable = true`), modules own all the plumbing. The user never writes `home-manager.users.fernando.programs.bat.enable = true` — they say "I want bat" and the module figures out what that means at every layer. Multi-user and multi-system support fall out of this model — if you need to explicitly "add" either, the abstraction is wrong.

### User → System, not System → User

The direction is always bottom-up: a user asks for a capability, the module handles system-wide dependencies as a side effect. The system-level setup is a consequence of user intent, never the other way around.

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

- **`requires`** = "enabling X auto-enables Y" — X is fundamentally useless without Y.
- **`mkIf userCfg.Y.enable`** = "only apply when Y is also enabled" — X works standalone but enhances Y when present.

| Relationship | Mechanism | Why |
|---|---|---|
| lazygit → git | `requires` | Lazygit IS a git UI — useless without git |
| 1password → git | `requires` | Module's purpose is git SSH signing — useless without git |
| git → fish | `mkIf` | Git works without fish; aliases are a bonus |
| eza → fish | `mkIf` | Eza works without fish; the `ls` alias is a bonus |
| bat → fish | `mkIf` | Bat works without fish; the `cat` alias is a bonus |
| starship → fish | `mkIf` | Starship works with any shell; fish prompt hook is a bonus |

**Rule of thumb:** if removing the dependency means the module still does something useful, use `mkIf`. If it becomes useless, use `requires`.

## Code style

- **Never use `default.nix`** — use explicit names matching the module: `opencode/opencode.nix`, not `opencode/default.nix`.
- 2-space indentation, UTF-8, LF line endings
- Format with `nixfmt` (nixfmt-rfc-style)
- Lint with `statix`
- Shell scripts linted with `shellcheck`
- Shell tools compose by calling existing tools — never reimplement another tool's logic. Extend the underlying tool if it's missing what you need.
- Pre-commit hooks enforce all of the above automatically

## Commit conventions

Conventional commits with scope: `feat(<scope>): description`, `fix(<scope>): description`, `chore(<scope>): description`. Scope is typically the module category or app name (e.g., `tmux`, `nvim`, `m1`, `hammerspoon`, `git`).
