local on_attach = function(client, bufnr)
    -- Mappings.
    -- See `:help vim.diagnostic.*` for documentation on any of the below functions
    local opts = {buffer = bufnr, remap = false}
    vim.keymap.set('n', '<space>e', function() vim.diagnostic.open_float() end, opts)
    vim.keymap.set('n', '[d', function() vim.diagnostic.goto_prev() end, opts)
    vim.keymap.set('n', ']d', function() vim.diagnostic.goto_next() end, opts)
    vim.keymap.set('n', 'gd', function() vim.lsp.buf.definition() end, opts)
    vim.keymap.set('n', 'gi', function() vim.lsp.buf.implementation() end, opts)
    vim.keymap.set('n', 'gr', function() vim.lsp.buf.references() end, opts)
    vim.keymap.set('n', 'K', function() vim.lsp.buf.hover() end, opts)
    vim.keymap.set({'n', 'i'}, '<C-s>', function() vim.lsp.buf.signature_help() end, opts)
    vim.keymap.set('n', '<leader>wa', function() vim.lsp.buf.add_workspace_folder() end, opts)
    vim.keymap.set('n', '<leader>wr', function() vim.lsp.buf.remove_workspace_folder() end, opts)
    vim.keymap.set('n', '<leader>D', function() vim.lsp.buf.type_definition() end, opts)
    vim.keymap.set('n', '<leader>rn', function() vim.lsp.buf.rename() end, opts)
    vim.keymap.set('n', '<leader>ca', function() vim.lsp.buf.code_action() end, opts)
    vim.keymap.set('n', '<leader>f', function() vim.lsp.buf.format() end, opts)

    -- Set autocommands conditional on server_capabilities
    if client.server_capabilities.documentHighlightProvider then
        local group = vim.api.nvim_create_augroup("LSPDocumentHighlight", {})
        vim.api.nvim_create_autocmd({ "CursorHold" }, {
            buffer=bufnr,
            group=group,
            callback = function()
                vim.lsp.buf.document_highlight()
            end,
        })
        vim.api.nvim_create_autocmd({ "CursorMoved" }, {
            buffer=bufnr,
            group=group,
            callback = function()
                vim.lsp.buf.clear_references()
            end,
        })
    end
    -- if client.server_capabilities.signatureHelpProvider then
    --     vim.api.nvim_create_autocmd({ "CursorHoldI" }, {
    --         buffer=bufnr,
    --         callback = function()
    --             vim.lsp.buf.signature_help()
    --         end,
    --     })
    -- end
    vim.api.nvim_create_autocmd({ "CursorHold" }, {
        buffer=bufnr,
        callback = function()
            vim.diagnostic.open_float(0, {focusable=false})
        end,
    })
    vim.lsp.handlers["textDocument/publishDiagnostics"] = vim.lsp.with(
    vim.lsp.diagnostic.on_publish_diagnostics, {
        virtual_text = {
            prefix = ""
        },
        severity_sort = true,
        underline = true,
        signs = true,
    }
    )

end


-- setup nvim-cmp
local cmp = require('cmp')

cmp.setup({
    snippet = {
        expand = function(args)
        -- vim.fn["vsnip#anonymous"](args.body) -- For `vsnip` users.
        -- require('luasnip').lsp_expand(args.body) -- For `luasnip` users.
        -- vim.fn["UltiSnips#Anon"](args.body) -- For `ultisnips` users.
        -- require'snippy'.expand_snippet(args.body) -- For `snippy` users.
        end,
    },
    mapping = cmp.mapping.preset.insert({
        ['<C-d>'] = cmp.mapping.scroll_docs(-4),
        ['<C-f>'] = cmp.mapping.scroll_docs(4),
        ['<C-Space>'] = cmp.mapping.complete(),
        -- ['<C-e>'] = cmp.mapping.abort(),
        ['<CR>'] = cmp.mapping.confirm({ select = true }),
    }),
    sources = cmp.config.sources({
        { name = 'nvim_lsp' },
        -- { name = 'vsnip' }, -- For vsnip users.
        -- { name = 'luasnip' }, -- For luasnip users.
        -- { name = 'ultisnips' }, -- For ultisnips users.
        -- { name = 'snippy' }, -- For snippy users.
    })
})



local capabilities = require('cmp_nvim_lsp').default_capabilities()


require'lspconfig'.pyright.setup{
    on_attach = function(client, bufnr)
        on_attach(client, bufnr)
        vim.keymap.set("n", "<leader>f", ":Black<CR>")
    end,
    capabilities = capabilities,
    -- settings = {
    --     python = {
    --         analysis = {
    --             -- stubPath = "/home/gshpychka/venvs/.typestubs",
    --             useLibraryCodeForTypes = false,
    --             diagnosticMode = "openFilesOnly",
    --             -- autoSearchPaths = false,
    --             typeCheckingMode = "basic",
    --             reportMissingTypeStubs = false,
    --             diagnosticSeverityOverrides = {
    --                 reportUninitializedInstanceVariable = "warning",
    --                 reportMissingImports = "error",
    --                 reportImportCycles = "warning",
    --                 reportDuplicateImport = "info",
    --                 reportOverlappingOverload = "warning",
    --                 reportIncompatibleMethodOverride = "warning",
    --                 reportIncompatibleVariableOverride = "warning",
    --                 strictParameterNoneValue = "info",
    --                 strictListInference = true,
    --                 strictDictionaryInference = true,
    --                 strictSetInference = true,
    --                 reportUnnecessaryCast = "info",
    --                 reportUnnecessaryComparison = "info",
    --                 reportUnnecessaryIsInstance = "info",
    --                 reportUnnecessaryTypeIgnoreComment = "info",
    --                 reportImplicitStringConcatenation = "warning",
    --                 reportCallInDefaultInitializer = "error",
    --                 reportPropertyTypeMismatch = "warning",
    --                 reportUntypedFunctionDecorator = "info",
    --                 reportUntypedClassDecorator = "info",
    --                 reportUntypedBaseClass = "info",
    --                 reportPrivateUsage = "warning",
    --                 reportConstantRedefinition = "warning",
    --                 reportMissingSuperCall = "warning",
    --                 reportUnknownParameterType = "none",
    --                 reportUnknownArgumentType = "none",
    --                 reportUnknownVariableType = "none",
    --                 reportUnknownMemberType = "none",
    --                 reportMissingParameterType = "none",
    --                 reportMissingTypeArgument = "none",
    --                 reportUnusedVariable = "info",
    --             }
    --         }
    --     }
    -- }
}

require'lspconfig'.tsserver.setup({
  capabilities = capabilities,
  on_attach = function(client, bufnr)
      client.server_capabilities.document_formatting = false
      client.server_capabilities.document_range_formatting = false

      local ts_utils = require("nvim-lsp-ts-utils")
      ts_utils.setup({})
      ts_utils.setup_client(client)

      -- buf_map(bufnr, "n", "gs", ":TSLspOrganize<CR>")
      -- buf_map(bufnr, "n", "gi", ":TSLspRenameFile<CR>")
      -- buf_map(bufnr, "n", "go", ":TSLspImportAll<CR>")

      on_attach(client, bufnr)
  end,
})

require'lspconfig'.lua_ls.setup({
  capabilities = capabilities,
  on_attach = on_attach,
  settings = {
    Lua = {
      runtime = {
        -- Tell the language server which version of Lua you're using (most likely LuaJIT in the case of Neovim)
        version = 'LuaJIT',
      },
      diagnostics = {
        -- Get the language server to recognize the `vim` global
        globals = {'vim'},
      },
      workspace = {
        -- Make the server aware of Neovim runtime files
        library = vim.api.nvim_get_runtime_file("", true),
      },
      -- Do not send telemetry data containing a randomized but unique identifier
      telemetry = {
        enable = false,
      },
    },
  },
})

require'lspconfig'.rnix.setup{
  capabilities = capabilities,
  on_attach = on_attach,
}

local null_ls = require('null-ls')

null_ls.setup({
    sources = {
        null_ls.builtins.diagnostics.eslint,
        null_ls.builtins.code_actions.eslint,
        null_ls.builtins.formatting.prettier
    },
    on_attach = on_attach
})
