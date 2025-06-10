local util = require("vim.lsp.util")

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

local M = {}

M.capabilities = vim.tbl_deep_extend(
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

function M.create_on_attach(formatting)
  return function(client, bufnr)
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
    if formatting then
      vim.api.nvim_create_autocmd({ "BufWritePre" }, {
        desc = "LSP formatting on write",
        callback = function()
          vim.lsp.buf.format({ bufnr = bufnr, name = client.name })
        end,
        buffer = bufnr,
      })
    end
  end
end

return M
