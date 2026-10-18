{ pkgs }:
{
  home = {
    programs.neovim = {
      plugins = with pkgs; [
        # ── AI autocomplete (minuet-ai, Codestral FIM) ─────
        # Requires CODESTRAL_API_KEY in the environment (free tier at
        # https://console.mistral.ai/codestral).
        #
        # The guard below is load-bearing: minuet does NOT validate the key.
        # codestral.lua calls straight into openai_base.lua, which does
        # `'Bearer ' .. utils.get_api_key(...)`. With no key that is a
        # concat-on-nil, thrown from a vim.schedule callback on every
        # completion trigger — i.e. constantly, while typing.
        # Skipping setup() entirely means no autocmds, so nothing can fire.
        {
          plugin = vimPlugins.minuet-ai-nvim;
          config = ''
            if vim.env.CODESTRAL_API_KEY and vim.env.CODESTRAL_API_KEY ~= "" then
            require('minuet').setup({
              provider = 'codestral',
              provider_options = {
                codestral = {
                  model = 'codestral-latest',
                  end_point = 'https://codestral.mistral.ai/v1/fim/completions',
                  api_key = 'CODESTRAL_API_KEY',
                  stream = true,
                  optional = {
                    max_tokens = 256,
                    stop = { '\n\n' },
                  },
                },
              },
              virtualtext = {
                auto_trigger_ft = { '*' },
                keymap = {
                  accept = '<C-y>',       -- accept full suggestion
                  accept_line = '<C-j>',  -- accept one line
                  next = '<A-]>',         -- cycle to next suggestion
                  prev = '<A-[>',         -- cycle to previous suggestion
                  dismiss = '<C-]>',      -- dismiss suggestion
                },
              },
            })
            end
          '';
        }

      ];
    };
  };
}
