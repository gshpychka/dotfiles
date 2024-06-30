local util = require("vim.lsp.util")
local function keymap_exists(lhs, mode)
  return vim.fn.maparg(lhs, mode) ~= nil
end


vim.api.nvim_create_autocmd({ "CursorHold" }, {
  callback = function()
    vim.diagnostic.open_float({
      focusable = false,
      close_events = { "BufLeave", "CursorMoved", "InsertEnter", "FocusLost" },
    })
  end,
})

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
end

-- LSP servers

require("lspconfig").pyright.setup({
  capabilities = capabilities,
  on_attach = on_attach,
})

require("lspconfig").lua_ls.setup({
  capabilities = capabilities,
  on_attach = on_attach,
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
      formate = {
        enable = false,
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
  on_attach = on_attach,
  settings = {
    ["nil"] = {
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
  on_attach = on_attach,
})

require("lspconfig").jsonls.setup({
  capabilities = capabilities,
  on_attach = on_attach,
  init_options = {
    provideFormatter = false,
  },
})

require("lspconfig").yamlls.setup({
  capabilities = capabilities,
  on_attach = on_attach,
})

require("lspconfig").bashls.setup({
  capabilities = capabilities,
  on_attach = on_attach,
})

require("lspconfig").zls.setup({
  on_attach = on_attach,
  capabilities = capabilities,
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
      6133, -- unused vars
    }),
  },
  on_attach = function(client, bufnr)
    vim.keymap.set("n", "md", function()
      local handler = function(_, result, ctx, config)
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
      vim.lsp.buf_request(bufnr, "textDocument/definition", util.make_position_params(), handler)
    end, { desc = "Create mark at definition" })

    vim.api.nvim_create_autocmd({ "BufWritePre" }, {
      desc = "tsserver fix imports",
      buffer = bufnr,
      callback = function()
        ts_api.remove_unused_imports(true)
        ts_api.add_missing_imports(true)
        ts_api.organize_imports(true)
      end,
    })

    on_attach(client, bufnr)
  end,
  capabilities = capabilities,
  settings = {
    tsserver_file_preferences = {
      includeInlayParameterNameHints = "all",
      includeInlayParameterNameHintsWhenArgumentMatchesName = true,
      includeInlayFunctionParameterTypeHints = true,
      includeInlayVariableTypeHints = true,
      includeInlayPropertyDeclarationTypeHints = true,
      includeInlayFunctionLikeReturnTypeHints = true,
      includeInlayEnumMemberValueHints = true,
      importModuleSpecifierPreference = "shortest",
    },
  },
})

require("lspconfig").eslint.setup({
  on_attach = function(client, bufnr)
    vim.keymap.set("n", "<leader>fo", function()
      vim.cmd("EslintFixAll")
    end, { desc = "Eslint formatting", remap = false, buffer = bufnr })
  end,
  settings = {
    workingDirectory = { mode = "auto" },
  },
})

local null_ls = require("null-ls")
null_ls.setup({
  debug = true,
  sources = {
    null_ls.builtins.diagnostics.flake8,
    null_ls.builtins.diagnostics.jsonlint,
    null_ls.builtins.formatting.fixjson.with({
      extra_args = {
        "--indent 2",
      },
    }),
    null_ls.builtins.formatting.prettier.with({
      -- only use prettier if it is installed in the project
      only_local = "node_modules/.bin",
    }),
    null_ls.builtins.formatting.autopep8,
    null_ls.builtins.formatting.isort,
    null_ls.builtins.formatting.black,
    null_ls.builtins.formatting.alejandra,
    null_ls.builtins.formatting.stylua,
    null_ls.builtins.formatting.yamlfmt.with({
      extra_args = {
        "-formatter",
        "retain_line_breaks_single=true,max_line_length=120",
        "-continue_on_error",
        "true",
      },
    }),
  },
  on_attach = function(client, bufnr)
    vim.api.nvim_create_autocmd({ "BufWritePre" }, {
      desc = "null_ls formatting on write",
      buffer = bufnr,
      callback = function()
        local params = util.make_formatting_params({})
        return client.request("textDocument/formatting", params, nil, bufnr)
      end,
    })
    if not keymap_exists("<leader>fo", "n") then
      -- Do not override if already mapped
      -- This is so that LSP-specific formatting keymap takes precedence
      vim.keymap.set("n", "<leader>fo", function()
        local params = util.make_formatting_params({})
        client.request("textDocument/formatting", params, nil, bufnr)
      end, {
        buffer = bufnr,
        remap = false,
        unique = true,
        desc = "Formatting",
      })
    end
  end,
})
