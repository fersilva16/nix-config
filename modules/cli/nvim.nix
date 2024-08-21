{ username, pkgs, lib, ... }:
let
  nvim-treesitter = pkgs.vimPlugins.nvim-treesitter.withPlugins (treesitter-plugins:
    with treesitter-plugins; [
      bash
      css
      html
      javascript
      json
      lua
      markdown
      nix
      python
      tsx
      typescript
      yaml
    ]);
in
{
  home-manager.users.${username} = {
    programs.neovim = {
      enable = true;
      defaultEditor = true;
      viAlias = true;
      vimAlias = true;
      vimdiffAlias = true;

      extraLuaConfig = ''
        vim.g.mapleader = ' '
        vim.g.maplocalleader = ' '

        vim.o.swapfile = false
        vim.o.hlsearch = false
        vim.wo.number = true
        vim.o.mouse = 'a'
        vim.o.clipboard = 'unnamedplus'
        vim.o.breakindent = true
        vim.o.undofile = true
        vim.o.ignorecase = true
        vim.o.smartcase = true
        vim.wo.signcolumn = 'yes'
        vim.o.updatetime = 250
        vim.o.timeoutlen = 300
        vim.o.completeopt = 'menuone,noselect'
        vim.o.termguicolors = true

        vim.g.netrw_keepdir = false
        vim.g.netrw_winsize = 30
        vim.g.netrw_banner = false
        vim.g.netrw_localcopydircmd = "cp -r"

        vim.keymap.set({ 'n', 'v' }, '<Space>', '<Nop>', { silent = true })

        vim.keymap.set('n', 'k', "v:count == 0 ? 'gk' : 'k'", { expr = true, silent = true })
        vim.keymap.set('n', 'j', "v:count == 0 ? 'gj' : 'j'", { expr = true, silent = true })

      '';

      plugins = with pkgs; [
        {
          plugin = vimPlugins.catppuccin-nvim;
          config = ''
            lua << EOF
              vim.cmd.colorscheme "catppuccin"
            EOF
          '';
        }
        {
          plugin = vimPlugins.supermaven-nvim;
          config = ''
            lua << EOF
              require('supermaven-nvim').setup({
                keymaps = {
                  accept_suggestion = "<Tab>",
                  clear_suggestion = "<C-]>",
                  accept_word = "<C-j>",
                },
              })
            EOF
          '';
        }
        {
          plugin = vimPlugins.alpha-nvim;
          config = ''
            lua << EOF
              local alpha = require('alpha')
                local dashboard = require('alpha.themes.dashboard')

              dashboard.section.header.val = {
                [[                                                                       ]],
                [[                                                                       ]],
                [[                                                                       ]],
                [[                                                                       ]],
                [[                                                                     ]],
                [[       ████ ██████           █████      ██                     ]],
                [[      ███████████             █████                             ]],
                [[      █████████ ███████████████████ ███   ███████████   ]],
                [[     █████████  ███    █████████████ █████ ██████████████   ]],
                [[    █████████ ██████████ █████████ █████ █████ ████ █████   ]],
                [[  ███████████ ███    ███ █████████ █████ █████ ████ █████  ]],
                [[ ██████  █████████████████████ ████ █████ █████ ████ ██████ ]],
                [[                                                                       ]],
                [[                                                                       ]],
                [[                                                                       ]],
              }

              alpha.setup(dashboard.opts)
            EOF
          '';
        }
        vimPlugins.nvim-comment
        {
          plugin = nvim-treesitter;
          config = ''
            lua << EOF
              vim.defer_fn(function()
                require('nvim-treesitter.configs').setup({
                  auto_install = false,

                  highlight = { enable = true },
                  indent = { enable = true },
                  incremental_selection = {
                    enable = true,
                    keymaps = {
                      init_selection = '<c-space>',
                      node_incremental = '<c-space>',
                      scope_incremental = '<c-s>',
                      node_decremental = '<M-space>',
                    },
                  },
                })
              end, 0)
            EOF
          '';
        }
        vimPlugins.telescope-fzf-native-nvim
        {
          plugin = vimPlugins.telescope-nvim;
          config = ''
            lua << EOF
              local telescope = require('telescope')

              telescope.setup {
                defaults = {
                  mappings = {
                    i = {
                      ['<C-u>'] = false,
                      ['<C-d>'] = false,
                    }
                  }
                }
              }

              telescope.load_extension('fzf')
            EOF
          '';
        }
        {
          plugin = vimPlugins.which-key-nvim;
          config = ''
            lua << EOF
              require('which-key').register({
                ["<space>"] = { "<cmd>Telescope buffers<cr>", "List buffers" },
                ["/"] = {
                  function ()
                    require('telescope.builtin').current_buffer_fuzzy_find(require('telescope.themes').get_dropdown {
                      winblend = 10,
                      previewer = false,
                    })
                  end,
                  "Fuzzy search in current buffer"
                },
                g = {
                  function ()
                    require('telescope.builtin').live_grep()
                  end,
                  "Live grep"
                },
                f = {
                  name = "file",
                  f = { "<cmd>Telescope find_files<cr>", "Find file" },
                  r = { "<cmd>Telescope oldfiles<cr>", "Find recent files", noremap = false },
                  n = { "<cmd>enew<cr>", "New File" },
                  s = { "<cmd>w<cr>", "Save file" },
                },
                c = {
                  name = "code",
                  a = { vim.lsp.buf.code_action, "Code Action" },
                  r = { vim.lsp.buf.rename, "Rename" },
                  s = {
                    name = "symbols",
                    d = { require('telescope.builtin').lsp_document_symbols, "Document symbols" },
                    w = { require('telescope.builtin').lsp_dynamic_workspace_symbols, "Workspace symbols" },
                  },
                },
                e = {
                  name = "editor",
                  w = { "<cmd>Telescope workspaces<cr>", "Workspaces" },
                  t = {
                    name = "tabs",
                    t = { "<cmd>tabnew<cr>", "New tab" },
                    s = { "<cmd>tab split<cr>", "Split tab" },
                    v = { "<cmd>vsplit<cr>", "Vertical split tab" },
                    c = { "<cmd>tabclose<cr>", "Close tab" },
                    o = { "<cmd>tabonly<cr>", "Only tab" },
                    l = { "<cmd>tabs<cr>", "List tabs" },
                    p = { "<cmd>tabprevious<cr>", "Previous tab" },
                    n = { "<cmd>tabnext<cr>", "Next tab" },
                    ["<S-<>"] = { "<cmd>tabmove -1<cr>", "Move tab left" },
                    ["<S->>"] = { "<cmd>tabmove +1<cr>", "Move tab right" },
                  },
                },
                q = {
                  name = "quit",
                  q = { "<cmd>qa!<CR>", "Quit all (will lose everything)", noremap = false },
                  a = { "<cmd>qa<CR>", "Quit all", noremap = false  }
                },
                h = {
                  name = "help",
                  k = { "<cmd>Telescope keymaps<CR>", "Keymaps" },
                },
                o = {
                  name = "open",
                  n = { "<cmd>Lexplore<CR>", "netrw" },
                  t = { "<cmd>Telescope<CR>", "Telescope" },
                  o = { "<cmd>Oil<CR>", "Oil" },
                  l = { "<cmd>Lazy<CR>", "Lazy" },
                },
                w = { "<c-w>", "window", noremap = false },
              }, { prefix = "<leader>" })
            EOF
          '';
        }
        vimPlugins.nvim-web-devicons
        vimPlugins.mini-nvim
        {
          plugin = vimPlugins.oil-nvim;
          config = ''
            lua << EOF
              require('oil').setup({
                default_file_explorer = true,
                columns = {
                  "icons",
                  "permissions",
                  "size",
                  "mtime"
                },
                delete_to_trash = true,
                cleanup_delay_ms = 1000,
                use_default_keymaps = true,
              })
            EOF
          '';
        }
        {
          plugin = vimPlugins.mason-nvim;
          config = ''
            lua << EOF
              require('mason').setup()
            EOF
          '';
        }
        {
          plugin = vimPlugins.mason-lspconfig-nvim;
          config = ''
            lua << EOF
              local mason_lspconfig = require 'mason-lspconfig'

              local on_attach = function(_, bufnr)
                require('which-key').register({
                  i = { require('telescope.builtin').lsp_implementations, "Goto implementation" },
                  r = { require('telescope.builtin').lsp_references, "Goto references" },
                  d = { vim.lsp.buf.definition, "Goto definition" },
                  t = { vim.lsp.buf.type_definition, "Type definition" },
                }, {
                  prefix = "<leader>c",
                  buffer = bufnr,
                  name = "code",
                })

                vim.api.nvim_buf_create_user_command(bufnr, 'Format', function(_)
                  vim.lsp.buf.format()
                end, { desc = 'Format current buffer with LSP' })
              end

              local servers = {
                lua_ls = {
                  Lua = {
                    workspace = { checkThirdParty = false },
                    telemetry = { enable = false },
                  },
                },
              }

              mason_lspconfig.setup {
                ensure_installed = vim.tbl_keys(servers),
              }

              mason_lspconfig.setup_handlers {
                function(server_name)
                  require('lspconfig')[server_name].setup {
                    capabilities = capabilities,
                    on_attach = on_attach,
                    settings = servers[server_name],
                    filetypes = (servers[server_name] or {}).filetypes,
                  }
                end,
              }
            EOF
          '';
        }
        vimPlugins.fidget-nvim
        vimPlugins.nvim-lspconfig
        vimPlugins.lazydev-nvim
        {
          plugin = vimPlugins.nvim-cmp;
          config = ''
            lua << EOF
              local cmp = require('cmp')

              cmp.setup {
                mapping = cmp.mapping.preset.insert {
                  ['<C-n>'] = cmp.mapping.select_next_item(),
                  ['<C-p>'] = cmp.mapping.select_prev_item(),
                  ['<C-d>'] = cmp.mapping.scroll_docs(-4),
                  ['<C-f>'] = cmp.mapping.scroll_docs(4),
                  ['<C-Space>'] = cmp.mapping.complete {},
                  ['<CR>'] = cmp.mapping.confirm {
                    behavior = cmp.ConfirmBehavior.Replace,
                    select = true,
                  },
                  ['<Tab>'] = cmp.mapping(function(fallback)
                    if cmp.visible() then
                      cmp.select_next_item()
                    else
                      fallback()
                    end
                  end, { 'i', 's' }),
                  ['<S-Tab>'] = cmp.mapping(function(fallback)
                    if cmp.visible() then
                      cmp.select_prev_item()
                    else
                      fallback()
                    end
                  end, { 'i', 's' }),
                },
                sources = {
                  { name = 'nvim_lsp' },
                },
              }
            EOF
          '';
        }
        {
          plugin = vimPlugins.cmp-nvim-lsp;
          config = ''
            lua << EOF
              local capabilities = vim.lsp.protocol.make_client_capabilities()
              capabilities = require('cmp_nvim_lsp').default_capabilities(capabilities)
            EOF
          '';
        }
      ];
    };
  };
}
