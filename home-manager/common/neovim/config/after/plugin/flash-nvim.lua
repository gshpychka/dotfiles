require("flash").setup({
  char = {
    enabled = false,
  },
})

vim.keymap.set("n", "s", require("flash").jump, { desc = "Flash" })
