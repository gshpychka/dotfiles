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

vim.lsp.config("*", {
  capabilities = vim.tbl_deep_extend(
    "force",
    vim.lsp.protocol.make_client_capabilities(),
    require("cmp_nvim_lsp").default_capabilities(),
    {
      workspace = {
        didChangeWorkspaceFolders = { dynamicRegistration = true },
      },
    }
  ),
  on_attach = function(client, bufnr)
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
    vim.api.nvim_create_autocmd({ "BufWritePre" }, {
      desc = "LSP formatting on write",
      callback = function()
        -- formatting can be registered dynamically, after attach
        if client:supports_method("textDocument/formatting") then
          vim.lsp.buf.format({ bufnr = bufnr, name = client.name })
        end
      end,
      buffer = bufnr,
    })
  end,
})
local default_on_attach = vim.lsp.config["*"].on_attach

local hidden_ts_codes = {
  [6196] = true, -- `'{0}' is declared but never used.`
  [6133] = true, -- `'{0}' is declared but its value is never read`
  [6134] = true, -- `Report errors on unused locals.`
  [6135] = true, -- `Report errors on unused parameters.`
  [6138] = true, -- `Property '{0}' is declared but its value is never read.`
}

---@param report lsp.FullDocumentDiagnosticReport|lsp.UnchangedDocumentDiagnosticReport
local function transform_ts_diagnostics(report)
  if report.kind ~= "full" then
    return
  end
  report.items = vim.tbl_filter(function(diag)
    return not hidden_ts_codes[diag.code]
  end, report.items)
  for _, diag in ipairs(report.items) do
    if diag.code then
      -- the translator's parser keys on a `TS<code>: ` message prefix
      local parsed = require("ts-error-translator").parse_errors("TS" .. diag.code .. ": " .. diag.message)
      if parsed[1] and parsed[1].improvedError then
        diag.message = parsed[1].improvedError.body
      end
    end
  end
end

-- Per-server config merged over the '*' defaults; an empty table just
-- enables the server with those defaults.
local servers = {
  pyright = {},

  lua_ls = {
    settings = {
      Lua = {
        runtime = {
          version = "LuaJIT",
        },
        diagnostics = {
          globals = { "vim" },
        },
        format = {
          enable = true,
        },
        workspace = {
          library = vim.api.nvim_get_runtime_file("", true),
          checkThirdParty = true,
        },
        telemetry = {
          enable = false,
        },
      },
    },
  },

  nixd = {
    settings = {
      nixd = {
        formatting = {
          command = { "nixfmt" },
        },
      },
    },
  },

  dockerls = {},

  jsonls = {
    init_options = {
      provideFormatter = true,
    },
  },

  yamlls = {},

  bashls = {},

  zls = {},

  terraformls = {},

  eslint = {
    on_attach = function(client, bufnr)
      -- eslint uses dynamic registration which neovim doesn't support
      -- https://github.com/microsoft/vscode-eslint/pull/1307
      client.server_capabilities.documentFormattingProvider = true
      if default_on_attach then
        default_on_attach(client, bufnr)
      end
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
  },

  biome = {},

  tsc = {
    handlers = {
      -- tsc serves diagnostics by pull
      ["textDocument/diagnostic"] = function(err, result, ctx)
        if result then
          transform_ts_diagnostics(result)
          for _, related in pairs(result.relatedDocuments or {}) do
            transform_ts_diagnostics(related)
          end
        end
        return vim.lsp.diagnostic.on_diagnostic(err, result, ctx)
      end,
    },
    on_attach = function(client, bufnr)
      -- eslint/biome own formatting
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
        vim.lsp.buf_request(
          bufnr,
          "textDocument/definition",
          util.make_position_params(0, client.offset_encoding),
          handler
        )
      end, { desc = "Create mark at definition", buffer = bufnr })

      vim.keymap.set("n", "<leader>fo", function()
        vim.lsp.buf.code_action({
          context = { only = { "source.organizeImports" }, diagnostics = {} },
          filter = function(_, client_id)
            return client_id == client.id
          end,
          apply = true,
        })
      end, { desc = "Organize imports", buffer = bufnr })

      if default_on_attach then
        default_on_attach(client, bufnr)
      end
    end,
    settings = {
      ["js/ts"] = {
        inlayHints = {
          parameterNames = {
            enabled = "all",
            suppressWhenArgumentMatchesName = false,
          },
        },
      },
    },
  },
}

for name, cfg in pairs(servers) do
  vim.lsp.config(name, cfg)
  vim.lsp.enable(name)
end
