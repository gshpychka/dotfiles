local lsp = require("lsp")
require("lspconfig").bashls.setup({
  capabilities = lsp.capabilities,
  on_attach = lsp.create_on_attach(true),
})
