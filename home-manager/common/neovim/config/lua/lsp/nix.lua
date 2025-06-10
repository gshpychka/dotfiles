local lsp = require("lsp")
require("lspconfig").nil_ls.setup({
  capabilities = lsp.capabilities,
  on_attach = lsp.create_on_attach(true),
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
