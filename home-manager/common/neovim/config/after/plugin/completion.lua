local has_words_before = function()
  unpack = unpack or table.unpack
  local line, col = unpack(vim.api.nvim_win_get_cursor(0))
  return col ~= 0 and vim.api.nvim_buf_get_lines(0, line - 1, line, true)[1]:sub(col, col):match("%s") == nil
end

vim.api.nvim_set_hl(0, "CmpItemKindSupermaven", { fg = "#6CC644" })

local cmp = require("cmp")
local lspkind = require("lspkind")
local luasnip = require("luasnip")

require("supermaven-nvim").setup({
  log_level = "warn",
  disable_keymaps = true,
  disable_inline_completion = true, -- disables inline completion for use with cmp
})

cmp.setup({
  snippet = {
    expand = function(args)
      require("luasnip").lsp_expand(args.body)
    end,
  },
  mapping = cmp.mapping.preset.insert({
    ["<C-d>"] = cmp.mapping.scroll_docs(-4),
    ["<C-f>"] = cmp.mapping.scroll_docs(4),
    ["<C-l>"] = cmp.mapping.complete(),
    ["<C-e>"] = cmp.mapping.abort(),
    ["<CR>"] = cmp.mapping({
      i = function(fallback)
        if cmp.visible() and cmp.get_active_entry() then
          cmp.confirm({
            behavior = cmp.ConfirmBehavior.Replace,
            select = false,
          })
        else
          fallback()
        end
      end,
    }),
    ["<Tab>"] = cmp.mapping(function(fallback)
      if cmp.visible() then
        cmp.select_next_item()
      elseif luasnip.expand_or_locally_jumpable() then
        luasnip.expand_or_jump()
      elseif has_words_before() then
        cmp.complete()
      else
        fallback()
      end
    end, { "i", "s" }),

    ["<S-Tab>"] = cmp.mapping(function(fallback)
      if cmp.visible() then
        cmp.select_prev_item()
      elseif luasnip.jumpable(-1) then
        luasnip.jump(-1)
      else
        fallback()
      end
    end, { "i", "s" }),
  }),
  sources = cmp.config.sources({
    { name = "supermaven", group_index = 2 },
    { name = "nvim_lsp", group_index = 2 },
    -- { name = 'luasnip' }, -- For luasnip users.
  }),
  formatting = {
    format = lspkind.cmp_format({
      mode = "symbol", -- show only symbol annotations
      maxwidth = 50, -- prevent the popup from showing more than provided characters (e.g 50 will not show more than 50 characters)
      ellipsis_char = "...", -- when popup menu exceed maxwidth, the truncated part would show ellipsis_char instead (must define maxwidth first)
      symbol_map = { Supermaven = "" },
    }),
  },
  experimental = {
    ghost_text = true,
  },
})

cmp.setup.filetype("lua", {
  sources = cmp.config.sources({
    { name = "nvim_lua", group_index = 2 },
    { name = "nvim_lsp", group_index = 2 },
    { name = "supermaven", group_index = 2 },
  }),
})
