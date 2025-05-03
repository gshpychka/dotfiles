local agitator = require("agitator")

vim.keymap.set("n", "<leader>tm", function()
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
      popup_last_line = '<J> Previous | <K> Next | <c-h> Copy SHA | [q]uit'
    })
  end,
  { desc = "git time machine" }
)
