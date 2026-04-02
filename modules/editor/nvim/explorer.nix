{ pkgs }:
{
  home = {
    programs.neovim = {
      initLua = ''
        -- ── Explorer which-key bindings ───────────────────
        require('which-key').add({
          { "<leader>e", "<cmd>Neotree toggle<cr>", desc = "Toggle file explorer" },
          { "<leader>;", function()
              local cur_buf = vim.api.nvim_get_current_buf()
              if vim.bo[cur_buf].filetype == 'neo-tree' then
                vim.cmd('wincmd p')
              else
                for _, win in ipairs(vim.api.nvim_list_wins()) do
                  local buf = vim.api.nvim_win_get_buf(win)
                  if vim.bo[buf].filetype == 'neo-tree' then
                    vim.api.nvim_set_current_win(win)
                    return
                  end
                end
              end
            end, desc = "Toggle focus file explorer" },
          { "<leader>E", group = "explorer views" },
          { "<leader>Ef", "<cmd>Neotree toggle reveal right<cr>", desc = "File tree" },
          { "<leader>Eg", "<cmd>Neotree toggle git_status right<cr>", desc = "Git status" },
          { "<leader>Eb", "<cmd>Neotree toggle buffers right<cr>", desc = "Buffers" },
          { "<leader>oo", "<cmd>Oil<CR>", desc = "Oil file explorer" },
        })
      '';

      plugins = with pkgs; [
        # ── Oil file explorer ──────────────────────────────
        {
          plugin = vimPlugins.oil-nvim;
          config = ''
            lua << EOF
              require('oil').setup({
                default_file_explorer = true,
                columns = {
                  "icon",
                  "permissions",
                  "size",
                  "mtime",
                },
                delete_to_trash = true,
                cleanup_delay_ms = 1000,
                use_default_keymaps = true,
                view_options = {
                  show_hidden = true,
                },
              })
            EOF
          '';
        }

        # ── Sidebar file tree + git status ─────────────────
        vimPlugins.nui-nvim
        {
          plugin = vimPlugins.neo-tree-nvim;
          config = ''
            lua << EOF
              -- Open neo-tree on startup
              vim.api.nvim_create_autocmd('VimEnter', {
                callback = function()
                  -- Only open if we're not opening a specific file via stdin or with args that are directories
                  if vim.fn.argc() == 0 then return end
                  vim.cmd('Neotree show right')
                end,
              })

              -- Also open when entering a buffer (covers opening nvim with a file)
              vim.api.nvim_create_autocmd('BufReadPost', {
                once = true,
                callback = function()
                  vim.schedule(function()
                    vim.cmd('Neotree show right')
                  end)
                end,
              })

              require('neo-tree').setup({
                close_if_last_window = true,
                popup_border_style = 'rounded',
                enable_git_status = true,
                enable_diagnostics = true,
                sort_case_insensitive = true,

                -- Sidebar on the right
                default_component_configs = {
                  indent = {
                    indent_size = 2,
                    with_markers = true,
                    indent_marker = "│",
                    last_indent_marker = "└",
                  },
                  icon = {
                    folder_closed = "",
                    folder_open = "",
                    folder_empty = "",
                  },
                  git_status = {
                    symbols = {
                      added     = "✚",
                      modified  = "",
                      deleted   = "✖",
                      renamed   = "󰁕",
                      untracked = "",
                      ignored   = "",
                      unstaged  = "󰄱",
                      staged    = "",
                      conflict  = "",
                    },
                  },
                },

                window = {
                  position = 'right',
                  width = 36,
                  mappings = {
                    ['<space>'] = 'none', -- don't conflict with leader
                  },
                },

                filesystem = {
                  follow_current_file = { enabled = true },
                  hijack_netrw_behavior = 'disabled', -- Oil handles netrw
                  use_libuv_file_watcher = true,
                  filtered_items = {
                    visible = true,
                    hide_dotfiles = false,
                    hide_gitignored = false,
                    never_show = { '.DS_Store' },
                  },
                },

                git_status = {
                  window = {
                    position = 'right',
                    mappings = {
                      ['<space>'] = 'none',
                    },
                  },
                  renderers = {
                    file = {
                      { "indent" },
                      { "icon" },
                      { "git_status", highlight = "NeoTreeDimText" },
                      { "name" },
                      { "diagnostics" },
                    },
                  },
                },

                buffers = {
                  follow_current_file = { enabled = true },
                  window = { position = 'right' },
                },
              })
            EOF
          '';
        }
      ];
    };
  };
}
