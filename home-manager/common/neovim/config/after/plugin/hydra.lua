local Hydra = require("hydra")
local agitator = require("agitator")
local gitsigns = require("gitsigns")

Hydra({
  name = "Git",
  config = {
    color = "pink",
    invoke_on_body = true,
    hint = false,
    on_enter = function()
      gitsigns.toggle_numhl(true)
      gitsigns.toggle_linehl(true)
      gitsigns.toggle_deleted(true)
    end,
    on_exit = function()
      gitsigns.toggle_numhl(false)
      gitsigns.toggle_linehl(false)
      gitsigns.toggle_deleted(false)

      -- wrapping in pcall to suppress the error if there is no blame window open
      pcall(agitator.git_blame_close)
    end,
  },
  mode = { "n", "x", "v" },
  body = "<leader>gg",
  heads = {
    {
      "J",
      function()
        if vim.wo.diff then
          return "]c"
        end
        vim.schedule(function()
          gitsigns.next_hunk()
        end)
        return "<Ignore>"
      end,
      { expr = true, desc = "next hunk" },
    },
    {
      "K",
      function()
        if vim.wo.diff then
          return "[c"
        end
        vim.schedule(function()
          gitsigns.prev_hunk()
        end)
        return "<Ignore>"
      end,
      { expr = true, desc = "prev hunk" },
    },
    {
      "s",
      gitsigns.stage_hunk,
      { silent = true, desc = "Stage hunk" },
    },
    { "S", gitsigns.stage_buffer,    { desc = "Stage buffer" } },
    {
      "r",
      gitsigns.reset_hunk,
      { silent = true, desc = "Reset hunk" },
    },
    {
      "R",
      gitsigns.reset_buffer,
      { silent = true, desc = "Reset buffer" },
    },
    { "u", gitsigns.undo_stage_hunk, { desc = "Unstage hunk" } },
    {
      "b",
      function()
        agitator.git_blame_toggle({
          sidebar_width = 40,
          formatter = function(commit)
            return commit.date.day
                .. "/"
                .. commit.date.month
                .. "/"
                .. commit.date.year
                .. " "
                .. commit.author
                .. " - "
                .. commit.summary
          end,
        })
      end,
      { desc = "blame sidebar" },
    },

    -- { "<Enter>", "<Cmd>Neogit<CR>", { exit = true, desc = "Neogit" } },
    {
      "<esc>",
      nil,
      { exit = true, nowait = true, desc = "exit" },
    },
  },
})

Hydra({
  name = "WindowManage",
  config = {
    color = "pink",
    invoke_on_body = true,
    hint = false,
  },
  mode = { "n", "x" },
  body = "<leader>w",
  heads = {
    { "<esc>", nil, { exit = true, nowait = true, desc = "exit" } },
    {
      "h",
      function()
        vim.cmd("wincmd h")
      end,
      { nowait = true, desc = "Move to left window" },
    },
    {
      "j",
      function()
        vim.cmd("wincmd j")
      end,
      { nowait = true, desc = "Move to window below" },
    },
    {
      "k",
      function()
        vim.cmd("wincmd k")
      end,
      { nowait = true, desc = "Move to window above" },
    },
    {
      "l",
      function()
        vim.cmd("wincmd l")
      end,
      { nowait = true, desc = "Move to right window" },
    },

    -- Window resizing
    {
      "+",
      function()
        vim.cmd("resize +5")
      end,
      { nowait = true, desc = "Increase height" },
    },
    {
      "-",
      function()
        vim.cmd("resize -5")
      end,
      { nowait = true, desc = "Decrease height" },
    },
    {
      "<",
      function()
        vim.cmd("vertical resize -5")
      end,
      { nowait = true, desc = "Decrease width" },
    },
    {
      ">",
      function()
        vim.cmd("vertical resize +5")
      end,
      { nowait = true, desc = "Increase width" },
    },

    -- Split management
    {
      "s",
      function()
        vim.cmd("split")
      end,
      { nowait = true, desc = "Split horizontally" },
    },
    {
      "v",
      function()
        vim.cmd("vsplit")
      end,
      { nowait = true, desc = "Split vertically" },
    },
    {
      "q",
      function()
        vim.cmd("close")
      end,
      { nowait = true, desc = "Close current window" },
    },

    -- Tab management
    {
      "t",
      function()
        vim.cmd("tabnew")
      end,
      { nowait = true, exit = true, desc = "New tab" },
    },
    {
      "T",
      function()
        vim.cmd("tabclose")
      end,
      { nowait = true, exit = true, desc = "Close current tab" },
    },
    -- barbar.nvim keymaps
    {
      "n",
      function()
        vim.cmd("BufferPrevious")
      end,
      { nowait = true, desc = "Next buffer" },
    },
    {
      "p",
      function()
        vim.cmd("BufferNext")
      end,
      { nowait = true, desc = "Previous buffer" },
    },
  },
})
