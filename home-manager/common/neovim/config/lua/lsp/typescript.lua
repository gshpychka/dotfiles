local lsp = require("lsp")
local util = require("vim.lsp.util")
local ts_api = require("typescript-tools.api")
require("typescript-tools").setup({
  handlers = {
    ["textDocument/references"] = function(err, result, ctx, config)
      local client = assert(vim.lsp.get_client_by_id(ctx.client_id))
      result = vim.tbl_filter(function(location)
        local item = util.locations_to_items({ location }, client.offset_encoding)[1]
        return not item.text:match("^import")
      end, result)
      return vim.lsp.handlers["textDocument/references"](err, result, ctx, config)
    end,
  },
  on_attach = function(client, bufnr)
    vim.keymap.set("n", "md", function()
      local handler = function(_, result, ctx, config)
        if result == nil or vim.tbl_isempty(result) then
          return nil
        end
        if vim.islist(result) then
          result = result[1]
        end
        local item = util.locations_to_items({ result }, client.offset_encoding)[1]
        local current_bufname = vim.api.nvim_buf_get_name(bufnr)
        if item.filename == current_bufname then
          vim.api.nvim_buf_set_mark(bufnr, "d", item.lnum, item.col, {})
          return nil
        else
          local relative_path = require("plenary.path"):new(item.filename):normalize()
          util.open_floating_preview({ "Definition is in another file:", "", relative_path }, "messages")
          return nil
        end
      end
      vim.lsp.buf_request(bufnr, "textDocument/definition", util.make_position_params(), handler)
    end, { desc = "Create mark at definition", buffer = bufnr })

    vim.keymap.set("n", "<leader>fo", function()
      ts_api.remove_unused_imports(true)
      ts_api.add_missing_imports(true)
      ts_api.organize_imports(true)
      vim.lsp.buf.format({ async = false, bufnr = bufnr, name = "eslint" })
    end, { desc = "Organize imports with tsserver and format with eslint", buffer = bufnr })

    lsp.create_on_attach(false)(client, bufnr)
  end,
  capabilities = lsp.capabilities,
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
  on_attach = lsp.create_on_attach(true),
  settings = {
    workingDirectory = { mode = "auto" },
    format = {
      enable = true,
    },
  },
})
