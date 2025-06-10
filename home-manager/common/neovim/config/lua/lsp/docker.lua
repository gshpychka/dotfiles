local lsp = require("lsp")
require("lspconfig").dockerls.setup({
  capabilities = lsp.capabilities,
  on_attach = lsp.create_on_attach(true),
})
