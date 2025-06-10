local lsp = require("lsp")
require("lspconfig").jsonls.setup({
  capabilities = lsp.capabilities,
  on_attach = lsp.create_on_attach(true),
  init_options = {
    provideFormatter = true,
  },
})
