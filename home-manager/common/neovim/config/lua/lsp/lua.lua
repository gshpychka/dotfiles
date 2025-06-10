local lsp = require("lsp")
require("lspconfig").lua_ls.setup({
  capabilities = lsp.capabilities,
  on_attach = lsp.create_on_attach(true),
  settings = {
    Lua = {
      runtime = { version = "LuaJIT" },
      diagnostics = { globals = { "vim" } },
      format = { enable = true },
      workspace = {
        library = vim.api.nvim_get_runtime_file("", true),
        checkThirdParty = true,
      },
      telemetry = { enable = false },
    },
  },
})
