{ pkgs }:
let
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
  home = {
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
      bash-language-server
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
      initLua = ''
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

        -- ── LSP which-key bindings ────────────────────────
        require('which-key').add({
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

          { "<leader>x", group = "diagnostics" },
          { "<leader>xd", function() vim.diagnostic.open_float() end, desc = "Line diagnostics" },
          { "<leader>xl", function() require('telescope.builtin').diagnostics() end, desc = "All diagnostics" },
          { "<leader>xn", function() vim.diagnostic.goto_next() end, desc = "Next diagnostic" },
          { "<leader>xp", function() vim.diagnostic.goto_prev() end, desc = "Previous diagnostic" },
        })
      '';

      plugins = with pkgs; [
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

        # ── LSP server definitions (needed for filetype/cmd defaults) ──
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

              -- Integrate autopairs with cmp
              local cmp_autopairs = require('nvim-autopairs.completion.cmp')
              cmp.event:on('confirm_done', cmp_autopairs.on_confirm_done())
            EOF
          '';
        }
      ];
    };
  };
}
