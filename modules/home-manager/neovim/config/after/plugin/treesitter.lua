-- treesitter highlighting and indentation for each buffer whose filetype
-- has an installed parser.
local group = vim.api.nvim_create_augroup("treesitter", { clear = true })
vim.api.nvim_create_autocmd("FileType", {
  group = group,
  callback = function(ev)
    local lang = vim.treesitter.language.get_lang(vim.bo[ev.buf].filetype)
    if not (lang and vim.treesitter.language.add(lang)) then
      return
    end
    vim.treesitter.start(ev.buf, lang)
    vim.bo[ev.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
  end,
})

-- folds are applied globally; buffers with no parser get no folds.
vim.o.foldmethod = "expr"
vim.o.foldexpr = "v:lua.vim.treesitter.foldexpr()"

-- incremental selection

local selection = {}

local function same_range(a, b)
  local a1, a2, a3, a4 = a:range()
  local b1, b2, b3, b4 = b:range()
  return a1 == b1 and a2 == b2 and a3 == b3 and a4 == b4
end

local function select_node(node)
  local srow, scol, erow, ecol = node:range()
  -- an end column of 0 means the range stops at the start of erow, so the last
  -- selected character sits at the end of the preceding line
  if ecol == 0 and erow > srow then
    erow = erow - 1
    ecol = #(vim.api.nvim_buf_get_lines(0, erow, erow + 1, false)[1] or "")
  end
  if vim.fn.mode():find("^[vV\22]") then
    vim.cmd("normal! \27")
  end
  vim.api.nvim_win_set_cursor(0, { srow + 1, scol })
  vim.cmd("normal! v")
  vim.api.nvim_win_set_cursor(0, { erow + 1, math.max(ecol - 1, 0) })
end

local function start()
  local node = vim.treesitter.get_node()
  if not node then
    return
  end
  selection[vim.api.nvim_get_current_buf()] = { node }
  select_node(node)
end

local function grow()
  local stack = selection[vim.api.nvim_get_current_buf()]
  if not stack or #stack == 0 then
    start()
    return
  end
  local node = stack[#stack]
  local parent = node:parent()
  while parent and same_range(parent, node) do
    parent = parent:parent()
  end
  if parent then
    stack[#stack + 1] = parent
    select_node(parent)
  end
end

local function shrink()
  local stack = selection[vim.api.nvim_get_current_buf()]
  if not stack or #stack < 2 then
    return
  end
  stack[#stack] = nil
  select_node(stack[#stack])
end

vim.keymap.set("n", "gnn", start, { desc = "Treesitter: select node" })
vim.keymap.set("x", "v", grow, { desc = "Treesitter: grow selection to parent node" })
vim.keymap.set("x", "V", shrink, { desc = "Treesitter: shrink selection to child node" })
