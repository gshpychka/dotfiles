local lint = require("lint")

lint.linters_by_ft = {
  nix = { "statix", "deadnix" },
}

-- statix reads ./statix.toml; deadnix runs strict — both match the flake checks
local group = vim.api.nvim_create_augroup("nvim-lint", { clear = true })
vim.api.nvim_create_autocmd({ "BufWritePost", "BufReadPost", "InsertLeave" }, {
  group = group,
  callback = function()
    require("lint").try_lint()
  end,
})
