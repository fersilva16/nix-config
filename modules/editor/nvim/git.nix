{ pkgs }:
{
  home = {
    programs.neovim = {
      initLua = ''
        -- ── Git which-key bindings ────────────────────────
        require('which-key').add({
          { "<leader>G", group = "git" },
          { "<leader>Gg", "<cmd>Neogit<cr>", desc = "Open Neogit (source control)" },
          { "<leader>Gc", "<cmd>Neogit commit<cr>", desc = "Commit" },
          { "<leader>Gp", "<cmd>Neogit push<cr>", desc = "Push" },
          { "<leader>Gl", "<cmd>Neogit pull<cr>", desc = "Pull" },
          { "<leader>Gd", "<cmd>DiffviewOpen<cr>", desc = "Diff view (all changes)" },
          { "<leader>Gf", "<cmd>DiffviewFileHistory %<cr>", desc = "File history" },
          { "<leader>GL", "<cmd>DiffviewFileHistory<cr>", desc = "Repo log" },
          { "<leader>Gq", "<cmd>DiffviewClose<cr>", desc = "Close diff view" },
          { "<leader>Gb", "<cmd>Telescope git_branches<cr>", desc = "Branches" },
          { "<leader>Gs", "<cmd>Telescope git_status<cr>", desc = "Status (telescope)" },
          { "<leader>Gh", group = "hunks" },
        })
      '';

      plugins = with pkgs; [
        {
          plugin = vimPlugins.gitsigns-nvim;
          config = ''
            lua << EOF
              require('gitsigns').setup({
                signs = {
                  add          = { text = '│' },
                  change       = { text = '│' },
                  delete       = { text = '_' },
                  topdelete    = { text = '‾' },
                  changedelete = { text = '~' },
                },
                on_attach = function(bufnr)
                  local gs = package.loaded.gitsigns

                  local function map(mode, l, r, opts)
                    opts = opts or {}
                    opts.buffer = bufnr
                    vim.keymap.set(mode, l, r, opts)
                  end

                  -- Navigation
                  map('n', ']h', gs.next_hunk, { desc = 'Next git hunk' })
                  map('n', '[h', gs.prev_hunk, { desc = 'Previous git hunk' })

                  -- Actions
                  map('n', '<leader>Ghs', gs.stage_hunk, { desc = 'Stage hunk' })
                  map('n', '<leader>Ghr', gs.reset_hunk, { desc = 'Reset hunk' })
                  map('n', '<leader>Ghp', gs.preview_hunk, { desc = 'Preview hunk' })
                  map('n', '<leader>Ghb', function() gs.blame_line({ full = true }) end, { desc = 'Blame line' })
                  map('n', '<leader>Ghd', gs.diffthis, { desc = 'Diff this' })
                end,
              })
            EOF
          '';
        }

        # ── Git: diffview ──────────────────────────────────
        {
          plugin = vimPlugins.diffview-nvim;
          config = ''
            lua << EOF
              require('diffview').setup({
                use_icons = true,
              })
            EOF
          '';
        }

        # ── Git: neogit (source control panel) ─────────────
        {
          plugin = vimPlugins.neogit;
          config = ''
            lua << EOF
              require('neogit').setup({
                integrations = {
                  telescope = true,
                  diffview = true,
                },
                signs = {
                  hunk = { " ", " " },
                  item = { "▸", "▾" },
                  section = { "▸", "▾" },
                },
              })
            EOF
          '';
        }
      ];
    };
  };
}
