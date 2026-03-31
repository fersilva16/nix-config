{
  username,
  pkgs,
  lib,
  ...
}:
let
  flexoki-neovim = pkgs.vimUtils.buildVimPlugin {
    pname = "flexoki-neovim";
    version = "2025-08-26";
    src = pkgs.fetchFromGitHub {
      owner = "kepano";
      repo = "flexoki-neovim";
      rev = "c3e2251e813d29d885a7cbbe9808a7af234d845d";
      sha256 = "0j6r1rm9g6mm5b5x2wddwyhh6wjagk0x9babs73ky081sgvlyl2f";
    };
  };

  nvim-treesitter = pkgs.vimPlugins.nvim-treesitter.withPlugins (
    treesitter-plugins: with treesitter-plugins; [
      bash
      css
      dart
      elixir
      go
      gomod
      gosum
      html
      javascript
      json
      lua
      markdown
      markdown_inline
      nix
      python
      rust
      toml
      tsx
      typescript
      yaml
    ]
  );
in
{
  home-manager.users.${username} = {
    # LSP servers and dev tools installed as Nix packages (no Mason needed)
    home.packages = with pkgs; [
      # Language servers
      lua-language-server
      nil # Nix LSP
      typescript-language-server
      vscode-langservers-extracted # HTML, CSS, JSON, ESLint
      pyright
      gopls
      rust-analyzer
      dart
      elixir-ls
      tailwindcss-language-server
      nodePackages.bash-language-server
      yaml-language-server
      taplo # TOML LSP
      marksman # Markdown LSP

      # Formatters & linters
      stylua
      nixfmt-rfc-style
      prettierd
      black
      gofumpt
      rustfmt
    ];

    programs.neovim = {
      enable = true;
      defaultEditor = true;
      viAlias = true;
      vimAlias = true;
      vimdiffAlias = true;

      initLua = ''
        -- ╔══════════════════════════════════════════╗
        -- ║          CORE OPTIONS                    ║
        -- ╚══════════════════════════════════════════╝
        vim.g.mapleader = ' '
        vim.g.maplocalleader = ' '

        vim.o.swapfile = false
        vim.o.hlsearch = false
        vim.wo.number = true
        vim.wo.relativenumber = true
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
        vim.o.scrolloff = 8
        vim.o.sidescrolloff = 8
        vim.o.cursorline = true
        vim.o.splitbelow = true
        vim.o.splitright = true
        vim.o.wrap = false
        vim.o.tabstop = 2
        vim.o.shiftwidth = 2
        vim.o.expandtab = true
        vim.o.showmode = false -- lualine shows the mode

        vim.keymap.set({ 'n', 'v' }, '<Space>', '<Nop>', { silent = true })

        -- Remap for dealing with word wrap
        vim.keymap.set('n', 'k', "v:count == 0 ? 'gk' : 'k'", { expr = true, silent = true })
        vim.keymap.set('n', 'j', "v:count == 0 ? 'gj' : 'j'", { expr = true, silent = true })

        -- ╔══════════════════════════════════════════╗
        -- ║    VS CODE-LIKE KEYBINDINGS              ║
        -- ╚══════════════════════════════════════════╝

        -- Move lines up/down (like Alt+Up/Down in VS Code)
        vim.keymap.set('n', '<A-j>', ':m .+1<CR>==', { desc = 'Move line down', silent = true })
        vim.keymap.set('n', '<A-k>', ':m .-2<CR>==', { desc = 'Move line up', silent = true })
        vim.keymap.set('v', '<A-j>', ":m '>+1<CR>gv=gv", { desc = 'Move selection down', silent = true })
        vim.keymap.set('v', '<A-k>', ":m '<-2<CR>gv=gv", { desc = 'Move selection up', silent = true })

        -- Indent/dedent in visual mode (stay in visual)
        vim.keymap.set('v', '<', '<gv', { desc = 'Dedent and reselect' })
        vim.keymap.set('v', '>', '>gv', { desc = 'Indent and reselect' })

        -- Window navigation (Ctrl+hjkl like VS Code pane switching)
        vim.keymap.set('n', '<C-h>', '<C-w>h', { desc = 'Move to left window' })
        vim.keymap.set('n', '<C-j>', '<C-w>j', { desc = 'Move to below window' })
        vim.keymap.set('n', '<C-k>', '<C-w>k', { desc = 'Move to above window' })
        vim.keymap.set('n', '<C-l>', '<C-w>l', { desc = 'Move to right window' })

        -- Resize windows with Ctrl+arrows
        vim.keymap.set('n', '<C-Up>', ':resize +2<CR>', { desc = 'Increase height', silent = true })
        vim.keymap.set('n', '<C-Down>', ':resize -2<CR>', { desc = 'Decrease height', silent = true })
        vim.keymap.set('n', '<C-Left>', ':vertical resize -2<CR>', { desc = 'Decrease width', silent = true })
        vim.keymap.set('n', '<C-Right>', ':vertical resize +2<CR>', { desc = 'Increase width', silent = true })

        -- Buffer navigation
        vim.keymap.set('n', '<S-h>', ':bprevious<CR>', { desc = 'Previous buffer', silent = true })
        vim.keymap.set('n', '<S-l>', ':bnext<CR>', { desc = 'Next buffer', silent = true })

        -- Better paste (don't replace register content)
        vim.keymap.set('v', 'p', '"_dP', { desc = 'Paste without yanking replaced text' })

        -- Clear search with Escape
        vim.keymap.set('n', '<Esc>', ':noh<CR>', { desc = 'Clear search highlight', silent = true })

        -- ╔══════════════════════════════════════════╗
        -- ║    WORD / LINE / FILE NAVIGATION          ║
        -- ╚══════════════════════════════════════════╝

        -- Opt+Left/Right → move by word (like Option+arrows in VS Code)
        vim.keymap.set({'n', 'v'}, '<A-Left>', 'b', { desc = 'Word back' })
        vim.keymap.set({'n', 'v'}, '<A-Right>', 'w', { desc = 'Word forward' })
        vim.keymap.set('i', '<A-Left>', '<C-o>b', { desc = 'Word back' })
        vim.keymap.set('i', '<A-Right>', '<C-o>w', { desc = 'Word forward' })

        -- Cmd+Left/Right → start/end of line (arrives as Home/End in terminal)
        vim.keymap.set({'n', 'v'}, '<Home>', '^', { desc = 'Start of line' })
        vim.keymap.set({'n', 'v'}, '<End>', '$', { desc = 'End of line' })
        vim.keymap.set('i', '<Home>', '<C-o>^', { desc = 'Start of line' })
        vim.keymap.set('i', '<End>', '<C-o>$', { desc = 'End of line' })

        -- Cmd+Up/Down → start/end of file (arrives as CSI u via extended-keys)
        vim.keymap.set({'n', 'v'}, '<C-Home>', 'gg', { desc = 'Start of file' })
        vim.keymap.set({'n', 'v'}, '<C-End>', 'G', { desc = 'End of file' })

        -- Opt+Backspace → delete word back (like Option+Backspace in VS Code)
        vim.keymap.set('i', '<A-BS>', '<C-w>', { desc = 'Delete word back' })

        -- ╔══════════════════════════════════════════╗
        -- ║    QUICK ACCESS (VS Code muscle memory)   ║
        -- ╚══════════════════════════════════════════╝

        -- Cmd+P → fuzzy find files in project (Ghostty sends CSI 80;6u)
        vim.keymap.set('n', '<C-S-p>', '<cmd>Telescope find_files<cr>', { desc = 'Find file in project' })
        -- Also bind Alt+p as fallback
        vim.keymap.set('n', '<A-p>', '<cmd>Telescope find_files<cr>', { desc = 'Find file in project' })

        -- Cmd+Shift+F → search text across project (Ghostty sends CSI 70;6u)
        vim.keymap.set('n', '<C-S-f>', function() require('telescope.builtin').live_grep() end, { desc = 'Search in project' })
        -- Also bind Alt+Shift+F as fallback
        vim.keymap.set('n', '<A-F>', function() require('telescope.builtin').live_grep() end, { desc = 'Search in project' })

        -- ╔══════════════════════════════════════════╗
        -- ║    CHEATSHEET (floating popup)            ║
        -- ╚══════════════════════════════════════════╝

        local function show_cheatsheet()
          local s = ' '
          local lines = {
            '  nvim cheatsheet              leader = Space',
            string.rep('─', 54),
            s,
            '  Quick Access',
            '  Cmd+p              find file in project',
            '  Cmd+Shift+f        search text in project',
            '  Space Space        switch buffer',
            '  Space /            search in current buffer',
            '  Space g            live grep',
            s,
            '  Navigation (arrows)     (native)',
            '  Opt+Left/Right          b / w      word',
            '  Cmd+Left/Right          ^ / $      line',
            '  Cmd+Up/Down             gg / G     file',
            '  Opt+Backspace           (insert)   del word',
            '  Alt+j / Alt+k           move line up/down',
            s,
            '  Files',
            '  Space ff           find file',
            '  Space fr           recent files',
            '  Space fn           new file',
            '  Space fs           save file',
            s,
            '  Code (LSP)',
            '  Space cd           go to definition',
            '  Space cR           go to references',
            '  Space ci           go to implementation',
            '  Space cr           rename symbol',
            '  Space ca           code action',
            '  Space cf           format file',
            '  Space ct           type definition',
            '  Space csd          document symbols',
            '  Space csw          workspace symbols',
            s,
            '  Diagnostics',
            '  Space xd           line diagnostics',
            '  Space xl           all diagnostics',
            '  Space xn / xp      next / prev diagnostic',
            s,
            '  Buffers & Tabs',
            '  Shift+h / Shift+l  prev / next buffer',
            '  Space bd           delete buffer',
            '  Space Tt           new tab',
            '  Space Tc           close tab',
            s,
            '  Splits & Windows',
            '  Space sv           vertical split',
            '  Space sh           horizontal split',
            '  Ctrl+h/j/k/l      move between windows',
            '  Ctrl+arrows        resize windows',
            s,
            '  Git (Source Control)',
            '  Space Gg           open neogit (stage/commit)',
            '  Space Gc           commit',
            '  Space Gp           push',
            '  Space Gl           pull',
            '  Space Gd           diff view (all changes)',
            '  Space Gf           current file history',
            '  Space GL           repo log',
            '  Space Gq           close diff view',
            '  Space Gb           branches',
            '  ]h / [h            next / prev hunk',
            '  Space Ghs          stage hunk',
            '  Space Ghr          reset hunk',
            '  Space Ghp          preview hunk',
            '  Space Ghb          blame line',
            s,
            '  Editing',
            '  Alt+j / Alt+k      move line down / up',
            '  < / >  (visual)    indent and reselect',
            '  gcc                toggle comment',
            '  sa" / sd" / sr"    surround add/del/replace',
            s,
            '  AI',
            '  Ctrl+y             accept supermaven suggestion',
            '  Ctrl+]             clear suggestion',
            '  Ctrl+j             accept word',
            '  Ctrl+.             toggle opencode',
            '  Ctrl+a             ask opencode',
            '  Ctrl+x             opencode actions',
            '  go / goo           send range/line to opencode',
            s,
            '  File Explorer',
            '  Space e            toggle sidebar (right)',
            '  Space ;            focus sidebar',
            '  Space Ef           sidebar: file tree',
            '  Space Eg           sidebar: git status',
            '  Space Eb           sidebar: buffers',
            '  Space oo           open Oil',
            '  -  (in Oil)        go up directory',
            s,
            '  General',
            '  Space hk           search keymaps',
            '  Space ?            this cheatsheet',
            '  Space qq           force quit all',
            s,
            '  press q to close',
          }

          local buf = vim.api.nvim_create_buf(false, true)
          vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
          vim.bo[buf].modifiable = false
          vim.bo[buf].bufhidden = 'wipe'

          local width = 54
          local height = #lines
          local win = vim.api.nvim_open_win(buf, true, {
            relative = 'editor',
            width = width,
            height = height,
            col = math.floor((vim.o.columns - width) / 2),
            row = math.floor((vim.o.lines - height) / 2),
            style = 'minimal',
            border = 'rounded',
            title = ' cheatsheet ',
            title_pos = 'center',
          })

          -- Highlight the header line
          vim.api.nvim_buf_add_highlight(buf, -1, 'Title', 0, 0, -1)

          -- Highlight section headers and dim separator/footer
          for i, line in ipairs(lines) do
            if line:match('^  [A-Z]') and not line:match('^ +[A-Z][a-z]+[+-]') then
              vim.api.nvim_buf_add_highlight(buf, -1, 'Function', i - 1, 0, -1)
            end
            if line:match('^─') or line:match('press q') then
              vim.api.nvim_buf_add_highlight(buf, -1, 'Comment', i - 1, 0, -1)
            end
          end

          -- Close on q or Esc
          local close = function() pcall(vim.api.nvim_win_close, win, true) end
          vim.keymap.set('n', 'q', close, { buffer = buf, silent = true })
          vim.keymap.set('n', '<Esc>', close, { buffer = buf, silent = true })
        end

        vim.keymap.set('n', '<leader>?', show_cheatsheet, { desc = 'Cheatsheet' })

        -- Highlight on yank
        local highlight_group = vim.api.nvim_create_augroup('YankHighlight', { clear = true })
        vim.api.nvim_create_autocmd('TextYankPost', {
          callback = function()
            vim.highlight.on_yank()
          end,
          group = highlight_group,
          pattern = '*',
        })

        -- ╔══════════════════════════════════════════╗
        -- ║    LSP (Neovim 0.11+ native API)         ║
        -- ╚══════════════════════════════════════════╝

        -- Shared capabilities (enhanced by cmp-nvim-lsp, loaded later)
        -- We defer the actual capability merging to LspAttach
        vim.api.nvim_create_autocmd('LspAttach', {
          callback = function(args)
            local client = vim.lsp.get_client_by_id(args.data.client_id)
            if not client then return end
            local bufnr = args.buf

            -- Enable inlay hints
            if client.server_capabilities.inlayHintProvider then
              vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
            end

            -- Format on save
            if client.server_capabilities.documentFormattingProvider then
              vim.api.nvim_create_autocmd('BufWritePre', {
                buffer = bufnr,
                callback = function()
                  vim.lsp.buf.format({ bufnr = bufnr })
                end,
              })
            end
          end,
        })

        -- Default config applied to all servers
        vim.lsp.config('*', {
          capabilities = vim.lsp.protocol.make_client_capabilities(),
        })

        -- Per-server configuration
        vim.lsp.config('lua_ls', {
          settings = {
            Lua = {
              workspace = { checkThirdParty = false },
              telemetry = { enable = false },
              completion = { callSnippet = 'Replace' },
            },
          },
        })

        vim.lsp.config('nil_ls', {
          settings = {
            ['nil'] = {
              formatting = { command = { "nixfmt" } },
            },
          },
        })

        vim.lsp.config('gopls', {
          settings = {
            gopls = {
              analyses = { unusedparams = true },
              staticcheck = true,
              gofumpt = true,
            },
          },
        })

        vim.lsp.config('rust_analyzer', {
          settings = {
            ['rust-analyzer'] = {
              checkOnSave = { command = 'clippy' },
              cargo = { allFeatures = true },
            },
          },
        })

        vim.lsp.config('elixirls', {
          cmd = { 'elixir-ls' },
        })

        -- Enable all servers (filetypes auto-detected via nvim-lspconfig definitions)
        vim.lsp.enable({
          'lua_ls',
          'nil_ls',
          'ts_ls',
          'pyright',
          'gopls',
          'rust_analyzer',
          'dartls',
          'elixirls',
          'tailwindcss',
          'html',
          'cssls',
          'jsonls',
          'bashls',
          'yamlls',
          'taplo',
          'marksman',
        })

        -- Diagnostic UI
        vim.diagnostic.config({
          virtual_text = { spacing = 4, prefix = '●' },
          signs = {
            text = {
              [vim.diagnostic.severity.ERROR] = ' ',
              [vim.diagnostic.severity.WARN] = ' ',
              [vim.diagnostic.severity.HINT] = '󰌵 ',
              [vim.diagnostic.severity.INFO] = ' ',
            },
          },
          underline = true,
          update_in_insert = false,
          severity_sort = true,
          float = {
            border = 'rounded',
            source = true,
          },
        })
      '';

      plugins = with pkgs; [
        # ── Core dependencies ──────────────────────────────
        vimPlugins.plenary-nvim

        # ── Colorscheme ────────────────────────────────────
        {
          plugin = flexoki-neovim;
          config = ''
            lua << EOF
              vim.cmd.colorscheme "flexoki-light"
            EOF
          '';
        }

        # ── Completion engine (must be before LSP setup) ───
        {
          plugin = vimPlugins.cmp-nvim-lsp;
          config = ''
            lua << EOF
              -- Enhance default LSP capabilities with cmp completions
              vim.lsp.config('*', {
                capabilities = require('cmp_nvim_lsp').default_capabilities(),
              })
            EOF
          '';
        }
        vimPlugins.cmp-buffer
        vimPlugins.cmp-path
        vimPlugins.cmp_luasnip
        {
          plugin = vimPlugins.luasnip;
          config = ''
            lua << EOF
              require('luasnip.loaders.from_vscode').lazy_load()
            EOF
          '';
        }
        vimPlugins.friendly-snippets

        # ── LSP progress UI ────────────────────────────────
        {
          plugin = vimPlugins.fidget-nvim;
          config = ''
            lua << EOF
              require('fidget').setup({})
            EOF
          '';
        }
        {
          plugin = vimPlugins.lazydev-nvim;
          config = ''
            lua << EOF
              require('lazydev').setup({})
            EOF
          '';
        }

        # ── Treesitter (grammars managed by Nix) ──────────
        {
          plugin = nvim-treesitter;
          config = ''
            lua << EOF
              -- Neovim 0.11+: treesitter highlight/indent are built-in
              -- Enable for all buffers that have a parser available
              vim.api.nvim_create_autocmd('FileType', {
                callback = function(args)
                  pcall(vim.treesitter.start, args.buf)
                end,
              })
            EOF
          '';
        }

        # ── Fuzzy finder ───────────────────────────────────
        vimPlugins.telescope-fzf-native-nvim
        {
          plugin = vimPlugins.telescope-nvim;
          config = ''
            lua << EOF
              local telescope = require('telescope')
              local actions = require('telescope.actions')

              telescope.setup {
                defaults = {
                  mappings = {
                    i = {
                      ['<C-u>'] = false,
                      ['<C-d>'] = false,
                      ['<C-j>'] = actions.move_selection_next,
                      ['<C-k>'] = actions.move_selection_previous,
                    }
                  },
                  file_ignore_patterns = { 'node_modules', '.git/', 'target/' },
                },
                pickers = {
                  find_files = {
                    hidden = true,
                  },
                },
              }

              telescope.load_extension('fzf')
            EOF
          '';
        }

        # ── Which-key (v3 API) ─────────────────────────────
        {
          plugin = vimPlugins.which-key-nvim;
          config = ''
            lua << EOF
              local wk = require('which-key')
              wk.setup({
                plugins = {
                  spelling = { enabled = true },
                },
              })

              wk.add({
                -- Top-level leader bindings
                { "<leader><space>", "<cmd>Telescope buffers<cr>", desc = "Switch buffer" },
                { "<leader>/", function()
                    require('telescope.builtin').current_buffer_fuzzy_find(
                      require('telescope.themes').get_dropdown { winblend = 10, previewer = false }
                    )
                  end, desc = "Search in buffer" },
                { "<leader>g", function() require('telescope.builtin').live_grep() end, desc = "Live grep" },

                -- File
                { "<leader>f", group = "file" },
                { "<leader>ff", "<cmd>Telescope find_files<cr>", desc = "Find file" },
                { "<leader>fr", "<cmd>Telescope oldfiles<cr>", desc = "Recent files" },
                { "<leader>fn", "<cmd>enew<cr>", desc = "New file" },
                { "<leader>fs", "<cmd>w<cr>", desc = "Save file" },

                -- Code (LSP)
                { "<leader>c", group = "code" },
                { "<leader>ca", vim.lsp.buf.code_action, desc = "Code action" },
                { "<leader>cr", vim.lsp.buf.rename, desc = "Rename symbol" },
                { "<leader>cf", function() vim.lsp.buf.format({ async = true }) end, desc = "Format file" },
                { "<leader>cd", vim.lsp.buf.definition, desc = "Go to definition" },
                { "<leader>cD", vim.lsp.buf.declaration, desc = "Go to declaration" },
                { "<leader>ci", function() require('telescope.builtin').lsp_implementations() end, desc = "Go to implementation" },
                { "<leader>cR", function() require('telescope.builtin').lsp_references() end, desc = "Go to references" },
                { "<leader>ct", vim.lsp.buf.type_definition, desc = "Type definition" },
                { "<leader>cs", group = "symbols" },
                { "<leader>csd", function() require('telescope.builtin').lsp_document_symbols() end, desc = "Document symbols" },
                { "<leader>csw", function() require('telescope.builtin').lsp_dynamic_workspace_symbols() end, desc = "Workspace symbols" },

                -- Explorer (neo-tree)
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

                -- Tabs
                { "<leader>T", group = "tabs" },
                { "<leader>Tt", "<cmd>tabnew<cr>", desc = "New tab" },
                { "<leader>Tc", "<cmd>tabclose<cr>", desc = "Close tab" },
                { "<leader>To", "<cmd>tabonly<cr>", desc = "Only this tab" },
                { "<leader>Tp", "<cmd>tabprevious<cr>", desc = "Previous tab" },
                { "<leader>Tn", "<cmd>tabnext<cr>", desc = "Next tab" },

                -- Splits (VS Code-like)
                { "<leader>sv", "<cmd>vsplit<cr>", desc = "Vertical split" },
                { "<leader>sh", "<cmd>split<cr>", desc = "Horizontal split" },
                { "<leader>se", "<C-w>=", desc = "Equal size splits" },
                { "<leader>sc", "<cmd>close<cr>", desc = "Close split" },

                -- Quit
                { "<leader>q", group = "quit" },
                { "<leader>qq", "<cmd>qa!<CR>", desc = "Force quit all" },
                { "<leader>qa", "<cmd>qa<CR>", desc = "Quit all" },

                -- Help
                { "<leader>h", group = "help" },
                { "<leader>hk", "<cmd>Telescope keymaps<CR>", desc = "Keymaps" },
                { "<leader>hh", "<cmd>Telescope help_tags<CR>", desc = "Help tags" },
                { "<leader>hm", "<cmd>Telescope man_pages<CR>", desc = "Man pages" },

                -- Open
                { "<leader>o", group = "open" },
                { "<leader>oo", "<cmd>Oil<CR>", desc = "Oil file explorer" },
                { "<leader>ot", "<cmd>Telescope<CR>", desc = "Telescope" },
                { "<leader>oa", function() require("opencode").toggle() end, desc = "Toggle opencode" },

                -- Buffers
                { "<leader>b", group = "buffer" },
                { "<leader>bd", "<cmd>bdelete<CR>", desc = "Delete buffer" },
                { "<leader>bn", "<cmd>bnext<CR>", desc = "Next buffer" },
                { "<leader>bp", "<cmd>bprevious<CR>", desc = "Previous buffer" },

                -- Diagnostics
                { "<leader>x", group = "diagnostics" },
                { "<leader>xd", function() vim.diagnostic.open_float() end, desc = "Line diagnostics" },
                { "<leader>xl", function() require('telescope.builtin').diagnostics() end, desc = "All diagnostics" },
                { "<leader>xn", function() vim.diagnostic.goto_next() end, desc = "Next diagnostic" },
                { "<leader>xp", function() vim.diagnostic.goto_prev() end, desc = "Previous diagnostic" },

                -- Window management
                { "<leader>w", proxy = "<C-w>", group = "window" },

                -- Git
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
            EOF
          '';
        }

        # ── LSP setup (Neovim 0.11+ native vim.lsp.config) ──
        #
        # nvim-lspconfig is still needed for its /lsp/*.lua server
        # definition files which register filetypes and default cmd/settings.
        # We just don't call require('lspconfig') anymore.
        vimPlugins.nvim-lspconfig

        # ── Completion (nvim-cmp) ──────────────────────────
        {
          plugin = vimPlugins.nvim-cmp;
          config = ''
            lua << EOF
              local cmp = require('cmp')
              local luasnip = require('luasnip')

              cmp.setup {
                snippet = {
                  expand = function(args)
                    luasnip.lsp_expand(args.body)
                  end,
                },
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
                    elseif luasnip.expand_or_locally_jumpable() then
                      luasnip.expand_or_jump()
                    else
                      fallback()
                    end
                  end, { 'i', 's' }),
                  ['<S-Tab>'] = cmp.mapping(function(fallback)
                    if cmp.visible() then
                      cmp.select_prev_item()
                    elseif luasnip.locally_jumpable(-1) then
                      luasnip.jump(-1)
                    else
                      fallback()
                    end
                  end, { 'i', 's' }),
                },
                sources = cmp.config.sources({
                  { name = 'nvim_lsp' },
                  { name = 'luasnip' },
                  { name = 'path' },
                }, {
                  { name = 'buffer' },
                }),
                window = {
                  completion = cmp.config.window.bordered(),
                  documentation = cmp.config.window.bordered(),
                },
              }
            EOF
          '';
        }

        # ── UI & Navigation ───────────────────────────────
        vimPlugins.nvim-web-devicons
        {
          plugin = vimPlugins.lualine-nvim;
          config = ''
            lua << EOF
              require('lualine').setup({
                options = {
                  theme = 'auto',
                  component_separators = { left = '│', right = '│' },
                  section_separators = { left = "", right = "" },
                },
                sections = {
                  lualine_a = { 'mode' },
                  lualine_b = { 'branch', 'diff', 'diagnostics' },
                  lualine_c = { { 'filename', path = 1 } },
                  lualine_x = { 'encoding', 'fileformat', 'filetype' },
                  lualine_y = { 'progress' },
                  lualine_z = {
                    'location',
                    {
                      function()
                        local ok, oc = pcall(require, "opencode")
                        if ok and oc.statusline then return oc.statusline() end
                        return ""
                      end,
                    },
                  },
                },
              })
            EOF
          '';
        }
        {
          plugin = vimPlugins.bufferline-nvim;
          config = ''
            lua << EOF
              require('bufferline').setup({
                options = {
                  diagnostics = 'nvim_lsp',
                  show_buffer_close_icons = true,
                  show_close_icon = false,
                  separator_style = 'thin',
                  offsets = {
                    {
                      filetype = 'oil',
                      text = 'File Explorer',
                      text_align = 'center',
                    },
                    {
                      filetype = 'neo-tree',
                      text = 'Explorer',
                      text_align = 'center',
                      highlight = 'Directory',
                      separator = true,
                    },
                  },
                },
              })
            EOF
          '';
        }
        {
          plugin = vimPlugins.indent-blankline-nvim;
          config = ''
            lua << EOF
              require('ibl').setup({
                indent = { char = '│' },
                scope = { enabled = true },
              })
            EOF
          '';
        }
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

        # ── Git: neogit (source control panel) ─────────────
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

        # ── File explorer ──────────────────────────────────
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

        # ── Editing helpers ────────────────────────────────
        vimPlugins.nvim-comment
        {
          plugin = vimPlugins.nvim-autopairs;
          config = ''
            lua << EOF
              require('nvim-autopairs').setup({})
              -- Integrate with cmp
              local cmp_autopairs = require('nvim-autopairs.completion.cmp')
              local cmp = require('cmp')
              cmp.event:on('confirm_done', cmp_autopairs.on_confirm_done())
            EOF
          '';
        }
        {
          plugin = vimPlugins.mini-nvim;
          config = ''
            lua << EOF
              -- Surround: add/change/delete surrounding brackets, quotes, etc.
              -- sa" to add quotes, sd" to delete, sr"' to replace " with '
              require('mini.surround').setup({})

              -- Highlight word under cursor
              require('mini.cursorword').setup({})
            EOF
          '';
        }

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

        # ── Dashboard ──────────────────────────────────────
        {
          plugin = vimPlugins.alpha-nvim;
          config = ''
            lua << EOF
              local alpha = require('alpha')
              local dashboard = require('alpha.themes.dashboard')

              dashboard.section.header.val = {
                [[                                                 ]],
                [[   ▄▄▄                                           ]],
                [[   ███      ▀▀           ▀▀       ▀▀             ]],
                [[   ███      ██  ███▄███▄ ██ ██ ██ ██  ███▄███▄   ]],
                [[   ███      ██  ██ ██ ██ ██ ██▄██ ██  ██ ██ ██   ]],
                [[   ████████ ██▄ ██ ██ ██ ██▄ ▀█▀  ██▄ ██ ██ ██   ]],
                [[                                                 ]],
              }

              dashboard.section.buttons.val = {
                dashboard.button("f", "  Find file", "<cmd>Telescope find_files<CR>"),
                dashboard.button("r", "  Recent files", "<cmd>Telescope oldfiles<CR>"),
                dashboard.button("g", "  Live grep", "<cmd>Telescope live_grep<CR>"),
                dashboard.button("e", "  New file", "<cmd>enew<CR>"),
                dashboard.button("q", "  Quit", "<cmd>qa<CR>"),
              }

              alpha.setup(dashboard.opts)
            EOF
          '';
        }
      ];
    };
  };
}
