local textcase = require("textcase")
textcase.setup({ default_keymappings_enabled = false })
require("telescope").load_extension("textcase")

vim.keymap.set("n", "<leader>cc", function()
  textcase.lsp_rename("to_camel_case")
end, { desc = "Rename to camelCase", remap = false })
vim.keymap.set(
  "n",
  "<leader>fcc",
  "<cmd>TextCaseOpenTelescopeLSPChange<CR>",
  { desc = "Change to any case with LSP", remap = false }
)
