{ pkgs }:
let
  version = "0.8.0";

  src = pkgs.fetchFromGitHub {
    owner = "cursortab";
    repo = "cursortab.nvim";
    rev = "v${version}";
    hash = "sha256-Y+q1NnQairgRE4lSbQ7pQn52ncobbRUmG7YuwbilDhY=";
  };

  # The plugin ships a Go daemon under server/ that the Lua side launches
  # from <plugin>/server/cursortab. Build it reproducibly with buildGoModule
  # instead of the upstream impure `cd server && go build` step.
  cursortab-server = pkgs.buildGoModule {
    pname = "cursortab-server";
    inherit version src;
    modRoot = "server";
    subPackages = [ "." ];
    vendorHash = "sha256-4S14Vm2Ju084uxB2Zlku4z5AmIZkNZkQpiNgYrcqIbg=";
    doCheck = false;
  };

  cursortab-nvim = pkgs.vimUtils.buildVimPlugin {
    pname = "cursortab.nvim";
    inherit version src;
    # The Lua resolves the daemon at <plugin>/server/cursortab; drop the
    # nix-built binary there so the runtime lookup succeeds.
    postInstall = ''
      mkdir -p $out/server
      cp ${cursortab-server}/bin/cursortab $out/server/cursortab
    '';
    # Loading the module spawns the daemon, so skip the require check.
    doInstallCheck = false;
    nvimSkipModule = true;
  };
in
{
  # Opt-in: the completion backend (Mercury API / local llama.cpp / Copilot)
  # is not wired yet, so keep it disabled by default until one is chosen.
  default = false;

  home = {
    programs.neovim.plugins = [
      {
        plugin = cursortab-nvim;
        config = ''
          -- Backend not configured yet. To enable, set `enabled = true`
          -- and point `provider` at a backend, e.g.:
          --   Mercury API (hosted): provider = { type = "mercuryapi", api_key_env = "MERCURY_AI_TOKEN" }
          --   Local llama.cpp:      provider = { type = "zeta-2", url = "http://localhost:8000" }
          --   GitHub Copilot:       provider = { type = "copilot" }
          require('cursortab').setup({
            enabled = false,
            keymaps = {
              accept = false,         -- avoid clobbering <Tab> until enabled
              partial_accept = false,
              trigger = false,
            },
          })
        '';
      }
    ];
  };
}
