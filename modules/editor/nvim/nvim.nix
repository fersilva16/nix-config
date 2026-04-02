{
  mkUserModule,
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
in
mkUserModule {
  name = "nvim";

  parts = {
    lsp = import ./lsp.nix { inherit pkgs; };
    git = import ./git.nix { inherit pkgs; };
    explorer = import ./explorer.nix { inherit pkgs; };
    ai = import ./ai.nix { inherit pkgs; };
  };

  home = {
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
                { "<leader>ot", "<cmd>Telescope<CR>", desc = "Telescope" },

                -- Buffers
                { "<leader>b", group = "buffer" },
                { "<leader>bd", "<cmd>bdelete<CR>", desc = "Delete buffer" },
                { "<leader>bn", "<cmd>bnext<CR>", desc = "Next buffer" },
                { "<leader>bp", "<cmd>bprevious<CR>", desc = "Previous buffer" },

                -- Window management
                { "<leader>w", proxy = "<C-w>", group = "window" },

                -- Splits
                { "<leader>s", group = "splits" },
              })
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

        # ── Editing helpers ────────────────────────────────
        vimPlugins.nvim-comment
        {
          plugin = vimPlugins.nvim-autopairs;
          config = ''
            lua << EOF
              require('nvim-autopairs').setup({})
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
