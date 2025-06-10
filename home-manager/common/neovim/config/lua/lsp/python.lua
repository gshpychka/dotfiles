local lsp = require("lsp")
require("lspconfig").pyright.setup({
  capabilities = lsp.capabilities,
  on_attach = lsp.create_on_attach(true),
})
