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
        # ── AI autocomplete (Supermaven) ───────────────────
        {
          plugin = vimPlugins.supermaven-nvim;
          config = ''
            lua << EOF
              require('supermaven-nvim').setup({
                keymaps = {
                  accept_suggestion = "<C-y>",
                  clear_suggestion = "<C-]>",
                  accept_word = "<C-j>",
                },
                color = {
                  suggestion_color = "#888888",
                },
                log_level = "off",
              })
            EOF
          '';
        }

        # ── opencode.nvim (AI agent integration) ──────────
        {
          plugin = vimPlugins.opencode-nvim;
          config = ''
            lua << EOF
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
            EOF
          '';
        }
      ];
    };
  };
}
