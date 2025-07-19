local textcase = require("textcase")
textcase.setup({ default_keymappings_enabled = false })
require("telescope").load_extension("textcase")

-- check if any lsp client supports rename
local function has_rename_capability()
  for _, client in pairs(vim.lsp.get_clients({ bufnr = 0 })) do
    if client.supports_method("textDocument/rename") then
      return true
    end
  end
  return false
end

vim.keymap.set("n", "<leader>cc", function()
  if has_rename_capability() then
    textcase.lsp_rename("to_camel_case")
  else
    -- fallback to text conversion only
    textcase.current_word("to_camel_case")
  end
end, { desc = "Rename to camelCase", remap = false })

vim.keymap.set("n", "<leader>fcc", function()
  if has_rename_capability() then
    vim.cmd("TextCaseOpenTelescopeLSPChange")
  else
    -- fallback to text conversion only
    vim.cmd("TextCaseOpenTelescope")
  end
end, { desc = "Change to any case", remap = false })
