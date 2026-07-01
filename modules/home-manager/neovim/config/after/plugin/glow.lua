-- render markdown
require("glow").setup({
  -- prevent it from downloading the binary
  glow_path = vim.fn.exepath("glow"),
  border = "rounded",
})

-- glow.nvim renders into a floating terminal window and has no toggle of its
-- own, so track the window handle to make one key open the preview and dismiss
-- it back to the raw buffer.
local preview_win = nil

local function is_open()
  return preview_win ~= nil and vim.api.nvim_win_is_valid(preview_win)
end

local function open()
  if is_open() then
    return
  end
  vim.cmd("Glow")
  -- :Glow enters its float, so the current window is now the preview.
  preview_win = vim.api.nvim_get_current_win()
end

local function toggle()
  if is_open() then
    vim.api.nvim_win_close(preview_win, true)
    preview_win = nil
  else
    open()
  end
end

-- Works from either side: opens from the raw buffer, closes from the float.
-- q and <Esc> also close the float (glow's own mappings).
vim.keymap.set("n", "<leader>md", toggle, { desc = "Toggle markdown preview (glow)" })

-- Show the preview automatically when a markdown file is opened for editing.
-- BufReadPost fires for real edits but not for telescope's previews, which load
-- buffer contents without a full read cycle.
vim.api.nvim_create_autocmd("BufReadPost", {
  group = vim.api.nvim_create_augroup("glow_auto_preview", { clear = true }),
  pattern = { "*.md", "*.markdown" },
  callback = function(args)
    if vim.bo[args.buf].buftype ~= "" then
      return
    end
    -- Defer so the markdown buffer is the active window when glow reads it.
    vim.schedule(function()
      if vim.api.nvim_get_current_buf() == args.buf then
        open()
      end
    end)
  end,
})
