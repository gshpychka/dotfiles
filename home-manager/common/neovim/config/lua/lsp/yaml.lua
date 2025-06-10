local lsp = require("lsp")
require("lspconfig").yamlls.setup({
  capabilities = lsp.capabilities,
  on_attach = lsp.create_on_attach(true),
})
