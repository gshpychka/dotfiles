vim.g.mapleader = " "
-- cannot be in after/plugin because has to run before plugin
vim.g.tmux_navigator_no_mappings = 1

vim.keymap.set("v", "p", '"_dP', { noremap = true, desc = "Paste without yanking" })
vim.keymap.set({ "n", "v" }, "<leader>y", '"+y', { noremap = true, desc = "Yank into system clipboard" })

vim.keymap.set("n", "<C-d>", "<C-d>zz", { desc = "Move down and keep cursor in the middle" })
vim.keymap.set("n", "<C-u>", "<C-u>zz", { desc = "Move up and keep cursor in the middle" })

vim.keymap.set("n", "n", "nzzzv", { desc = "Next result in the middle of the screen" })
vim.keymap.set("n", "N", "Nzzzv", { desc = "Previous result in the middle of the screen" })

-- Toggle displaying absolute line numbers instead of relative
local default_statuscolumn = vim.o.statuscolumn

vim.keymap.set("n", "<leader>ln", function()
  if vim.o.statuscolumn == default_statuscolumn then
    vim.o.statuscolumn = "%=%{v:virtnum < 1 ? (v:lnum < 10 ? v:lnum . '  ' : v:lnum) : ''}%=%s"
  else
    vim.o.statuscolumn = default_statuscolumn
  end
end, { desc = "Toggle absolute line numbers" })

vim.keymap.set("n", "]q", ":cnext<CR>", { desc = "Go to the next item in the Quickfix list" })
vim.keymap.set("n", "[q", ":cprevious<CR>", { desc = "Go to the previous item in the Quickfix list" })

vim.keymap.set("n", "<leader>e", function()
  vim.diagnostic.open_float({
    focusable = true,
    -- close_events = { "BufLeave", "CursorMoved", "InsertEnter", "FocusLost" },
  })
end, { desc = "Open diagnostics popup" })

vim.keymap.set("n", "[d", function()
  vim.diagnostic.jump({ count = -1, _highest = true })
end, { desc = "Go to previous highest diagnostic" })

vim.keymap.set("n", "]d", function()
  vim.diagnostic.jump({ count = 1, _highest = true })
end, { desc = "Go to next highest diagnostic" })

vim.keymap.set("n", "K", vim.lsp.buf.hover, { desc = "LSP hover" })

vim.keymap.set({ "n", "i" }, "<C-s>", vim.lsp.buf.signature_help, { desc = "Signature help" })

require("inc_rename").setup({})
vim.keymap.set("n", "<leader>rn", ":IncRename ", { desc = "Rename" })

vim.keymap.set("n", "<leader>cda", vim.lsp.buf.code_action, { desc = "Code action" })

vim.keymap.set("n", "<leader>il", function()
  vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({ bufnr = 0 }))
end, { desc = "Toggle inlay hints" })

vim.keymap.set({ "n" }, "<leader>fo", function()
  vim.lsp.buf.format({
    async = true,
    timeout_ms = 10000,
    filter = function(client)
      return client.name ~= "typescript-tools"
    end,
  })
end, { desc = "LSP formatting" })

local function toggle_quickfix()
  local quickfix_open = false
  for _, win in ipairs(vim.fn.getwininfo()) do
    if win.quickfix == 1 then
      quickfix_open = true
      break
    end
  end
  if quickfix_open then
    vim.cmd("cclose")
  else
    vim.cmd("copen")
  end
end

vim.keymap.set(
  { "n" },
  "<leader>qf",
  toggle_quickfix,
  { noremap = true, silent = true, desc = "Toggle the quickfix window" }
)
