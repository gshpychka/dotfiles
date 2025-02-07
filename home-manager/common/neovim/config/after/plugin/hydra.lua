local Hydra = require("hydra")
local agitator = require("agitator")
local gitsigns = require("gitsigns")
local ts_builtin = require("telescope.builtin")

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
    { "S", gitsigns.stage_buffer, { desc = "Stage buffer" } },
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
    { "p", gitsigns.preview_hunk, { desc = "Preview hunk" } },
    { "d", gitsigns.diffthis, { nowait = true, desc = "Diff" } },
    {
      "D",
      function()
        ts_builtin.git_branches({
          prompt_title = "Choose a branch to diff against",
          previewer = false,
          hidden = true,
          attach_mappings = function(prompt_bufnr, map)
            map("i", "<CR>", function()
              require("telescope.actions").close(prompt_bufnr) -- close the picker
              local selection = require("telescope.actions.state").get_selected_entry()
              -- Use gitsigns.diffthis with the chosen branch
              vim.cmd("DiffviewOpen " .. selection.value)
            end)
            return true
          end,
        })
      end,
      { desc = "Choose a branch to diff against" },
    },
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
    {
      "B",
      function()
        local commit_sha = require("agitator").git_blame_commit_for_line()
        vim.cmd("DiffviewOpen " .. commit_sha .. "^.." .. commit_sha)
      end,
      { desc = "diff blame commit" },
    },
    {
      "<leader>fc",
      ts_builtin.git_commits,
      { desc = "Telescope Git commits" },
    },
    {
      "<leader>fbc",
      ts_builtin.git_bcommits,
      { desc = "Telescope Git buffer commits" },
    },
    {
      "<leader>fbc",
      ts_builtin.git_bcommits_range,
      { mode = "v", desc = "Telescope Git commits for range" },
    },
    {
      "<leader>fbr",
      ts_builtin.git_branches,
      { desc = "Telescope Git branches" },
    },
    {
      "<leader>fgb",
      agitator.search_git_branch,
      { desc = "grep in a specific git branch" },
    },
    {
      "<leader>fgf",
      agitator.open_file_git_branch,
      { desc = "open a file in a specific git branch" },
    },
    {
      "<leader>fs",
      ts_builtin.git_status,
      { desc = "Telescope Git status" },
    },
    {
      "<leader>tm",
      function()
        agitator.git_time_machine({
          use_current_win = true,
          set_custom_shortcuts = function(bufnr)
            vim.keymap.set("n", "J", function()
              require("agitator").git_time_machine_previous()
            end, { buffer = bufnr })
            vim.keymap.set("n", "K", function()
              require("agitator").git_time_machine_next()
            end, { buffer = bufnr })
            vim.keymap.set("n", "<c-h>", function()
              require("agitator").git_time_machine_copy_sha()
            end, { buffer = bufnr })
            vim.keymap.set("n", "q", function()
              require("agitator").git_time_machine_quit()
            end, { buffer = bufnr })
          end,
        })
      end,
      { desc = "git time machine" },
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
