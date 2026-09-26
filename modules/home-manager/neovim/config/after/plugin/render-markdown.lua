-- render markdown in place: decorations are extmarks over the real buffer, so
-- it stays editable. Normal mode shows the rendered view except on the cursor
-- line (anti-conceal), insert mode shows the raw text.
require("render-markdown").setup({
  file_types = { "markdown" },
})

-- Per-buffer so toggling one file to raw leaves other markdown buffers rendered.
vim.keymap.set("n", "<leader>md", function()
  require("render-markdown").buf_toggle()
end, { desc = "Toggle markdown rendering" })
