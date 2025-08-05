local util = require("vim.lsp.util")

-- vim.api.nvim_create_autocmd({ "CursorHold" }, {
--   callback = function()
--     vim.diagnostic.open_float({
--       focusable = false,
--       close_events = { "BufLeave", "CursorMoved", "InsertEnter", "FocusLost" },
--     })
--   end,
-- })

vim.diagnostic.config({
  virtual_text = {
    prefix = " ",
    source = false,
  },
  update_in_insert = false,
  severity_sort = true,
  underline = true,
  float = {
    header = "",
    prefix = "",
    border = "rounded",
    scope = "line",
    source = false,
  },
})

local capabilities = vim.tbl_deep_extend(
  "force",
  vim.lsp.protocol.make_client_capabilities(),
  require("cmp_nvim_lsp").default_capabilities(),
  {
    workspace = {
      didChangeWatchedFiles = { dynamicRegistration = true },
      didChangeWorkspaceFolders = { dynamicRegistration = true },
    },
  }
)

local create_on_attach = function()
  local on_attach = function(client, bufnr)
    if client.server_capabilities.documentHighlightProvider then
      local group = vim.api.nvim_create_augroup("LSPDocumentHighlight", {})
      vim.api.nvim_create_autocmd({ "CursorHold" }, {
        desc = "LSP highlight symbol",
        buffer = bufnr,
        group = group,
        callback = vim.lsp.buf.document_highlight,
      })
      vim.api.nvim_create_autocmd({ "CursorMoved" }, {
        desc = "Clear LSP highlighting",
        buffer = bufnr,
        group = group,
        callback = vim.lsp.buf.clear_references,
      })
    end
    if client.server_capabilities.documentFormattingProvider then
      vim.api.nvim_create_autocmd({ "BufWritePre" }, {
        desc = "LSP formatting on write",
        callback = function()
          vim.lsp.buf.format({ bufnr = bufnr, name = client.name })
        end,
        buffer = bufnr,
      })
    end
  end
  return on_attach
end

-- LSP servers

require("lspconfig").pyright.setup({
  capabilities = capabilities,
  on_attach = create_on_attach(),
})

require("lspconfig").lua_ls.setup({
  capabilities = capabilities,
  on_attach = create_on_attach(),
  settings = {
    Lua = {
      runtime = {
        -- Tell the language server which version of Lua you're using (most likely LuaJIT in the case of Neovim)
        version = "LuaJIT",
      },
      diagnostics = {
        -- Get the language server to recognize the `vim` global
        globals = { "vim" },
      },
      format = {
        enable = true,
      },
      workspace = {
        -- Make the server aware of Neovim runtime files
        library = vim.api.nvim_get_runtime_file("", true),
        checkThirdParty = true,
      },
      -- Do not send telemetry data containing a randomized but unique identifier
      telemetry = {
        enable = false,
      },
    },
  },
})

require("lspconfig").nil_ls.setup({
  capabilities = capabilities,
  on_attach = create_on_attach(),
  settings = {
    ["nil"] = {
      formatting = {
        command = { "nixfmt" },
      },
      nix = {
        flake = {
          autoEvalInputs = false,
          autoArchive = false,
        },
      },
    },
  },
})

require("lspconfig").dockerls.setup({
  capabilities = capabilities,
  on_attach = create_on_attach(),
})

require("lspconfig").jsonls.setup({
  capabilities = capabilities,
  on_attach = create_on_attach(),
  init_options = {
    provideFormatter = true,
  },
})

require("lspconfig").yamlls.setup({
  capabilities = capabilities,
  on_attach = create_on_attach(),
})

require("lspconfig").bashls.setup({
  capabilities = capabilities,
  on_attach = create_on_attach(),
})

require("lspconfig").zls.setup({
  capabilities = capabilities,
  on_attach = create_on_attach(),
})

require("ts-error-translator").setup({
  auto_override_publish_diagnostics = true,
})

local ts_api = require("typescript-tools.api")
require("typescript-tools").setup({
  handlers = {
    -- Exclude imports from references
    -- TODO: exclude current line
    ["textDocument/references"] = function(err, result, ctx, config)
      local client = assert(vim.lsp.get_client_by_id(ctx.client_id))

      result = vim.tbl_filter(function(location)
        -- `util.locations_to_items()` changes the order,
        -- so calling it for each result separately
        local item = util.locations_to_items({ location }, client.offset_encoding)[1]
        return not item.text:match("^import")
      end, result)

      return vim.lsp.handlers["textDocument/references"](err, result, ctx, config)
    end,
    ["textDocument/publishDiagnostics"] = ts_api.filter_diagnostics({
      6196, -- `'{0}' is declared but never used.`
      6133, -- `'{0}' is declared but its value is never read`
      6134, -- `Report errors on unused locals.`
      6135, -- `Report errors on unused parameters.`
      6138, -- `Property '{0}' is declared but its value is never read.`
    }),
  },
  on_attach = function(client, bufnr)
    -- Disable formatting for typescript-tools (use eslint/biome instead)
    client.server_capabilities.documentFormattingProvider = false
    vim.keymap.set("n", "md", function()
      local handler = function(_, result, _, _)
        if result == nil or vim.tbl_isempty(result) then
          return nil
        end
        if vim.islist(result) then
          -- Hack: in case of multiple results, pick the first one
          result = result[1]
        end
        local item = util.locations_to_items({ result }, client.offset_encoding)[1]

        local current_bufname = vim.api.nvim_buf_get_name(bufnr)
        if item.filename == current_bufname then
          vim.api.nvim_buf_set_mark(bufnr, "d", item.lnum, item.col, {})
          return nil
        else
          -- If definition is in a different file, show the path
          local relative_path = require("plenary.path"):new(item.filename):normalize()
          util.open_floating_preview({ "Definition is in another file:", "", relative_path }, "messages")
          return nil
        end
      end
      vim.lsp.buf_request(bufnr, "textDocument/definition", util.make_position_params(0, client.offset_encoding), handler)
    end, { desc = "Create mark at definition", buffer = bufnr })

    vim.keymap.set("n", "<leader>fo", function()
      ts_api.remove_unused_imports(true)
      ts_api.add_missing_imports(true)
      ts_api.organize_imports(true)
    end, { desc = "Organize imports with tsserver", buffer = bufnr })

    create_on_attach()(client, bufnr)
  end,
  capabilities = capabilities,
  settings = {
    separate_diagnostic_server = true,
    tsserver_file_preferences = {
      includeInlayParameterNameHints = "all",
      includeInlayParameterNameHintsWhenArgumentMatchesName = true,
      includeInlayFunctionParameterTypeHints = true,
      includeInlayVariableTypeHints = true,
      includeInlayPropertyDeclarationTypeHints = true,
      includeInlayFunctionLikeReturnTypeHints = true,
      includeInlayEnumMemberValueHints = true,
      importModuleSpecifierPreference = "shortest",
      tsserver_max_memory = 8192,
    },
  },
})

require("lspconfig").eslint.setup({
  on_attach = function(client, bufnr)
    -- eslint uses dynamic registration which neovim doesn't support
    -- https://github.com/microsoft/vscode-eslint/pull/1307
    client.server_capabilities.documentFormattingProvider = true
    create_on_attach()(client, bufnr)
  end,
  -- only use flat config files (eslint.config.*)
  -- .eslintrc.* files are deprecated, see https://eslint.org/docs/latest/use/configure/migration-guide
  root_dir = require("lspconfig.util").root_pattern(
    "eslint.config.js",
    "eslint.config.mjs",
    "eslint.config.cjs",
    "eslint.config.ts",
    "eslint.config.mts",
    "eslint.config.cts"
  ),
  settings = {
    workingDirectory = { mode = "auto" },
    format = {
      enable = true,
    },
  },
})

require("lspconfig").biome.setup({
  on_attach = create_on_attach(),
})
