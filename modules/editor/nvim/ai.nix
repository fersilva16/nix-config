{ pkgs }:
{
  home = {
    programs.neovim = {
      initLua = ''
        -- ── AI which-key bindings ─────────────────────────
        require('which-key').add({
          { "<leader>oa", function() require("opencode").toggle() end, desc = "Toggle opencode" },
        })
      '';

      plugins = with pkgs; [
        # ── AI autocomplete (minuet-ai, Codestral FIM) ─────
        # Requires CODESTRAL_API_KEY in the environment (free tier at
        # https://console.mistral.ai/codestral). Without it, completions
        # are simply silent.
        {
          plugin = vimPlugins.minuet-ai-nvim;
          config = ''
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
          '';
        }

        # ── opencode.nvim (AI agent integration) ──────────
        {
          plugin = vimPlugins.opencode-nvim;
          config = ''
            vim.o.autoread = true -- Required for opencode edit reloading

            ---@type opencode.Opts
            vim.g.opencode_opts = {}

            -- Ask opencode about selection/cursor
            vim.keymap.set({ "n", "x" }, "<C-a>", function() require("opencode").ask("@this: ", { submit = true }) end, { desc = "Ask opencode" })
            -- Select from opencode actions (prompts, commands)
            vim.keymap.set({ "n", "x" }, "<C-x>", function() require("opencode").select() end, { desc = "opencode actions" })
            -- Toggle opencode TUI
            vim.keymap.set({ "n", "t" }, "<C-.>", function() require("opencode").toggle() end, { desc = "Toggle opencode" })

            -- Operator mode: send range to opencode (supports dot-repeat)
            vim.keymap.set({ "n", "x" }, "go", function() return require("opencode").operator("@this ") end, { desc = "Send range to opencode", expr = true })
            vim.keymap.set("n", "goo", function() return require("opencode").operator("@this ") .. "_" end, { desc = "Send line to opencode", expr = true })

            -- Remap increment/decrement since we took <C-a>/<C-x>
            vim.keymap.set("n", "+", "<C-a>", { desc = "Increment", noremap = true })
            vim.keymap.set("n", "-", "<C-x>", { desc = "Decrement", noremap = true })
          '';
        }
      ];
    };
  };
}
