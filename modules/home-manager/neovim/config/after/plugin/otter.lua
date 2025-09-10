local otter = require("otter")

-- Function to preprocess Nix escape sequences and interpolations
local function preprocess_nix_escapes(content)
  -- Only process if we're in a Nix file
  if vim.bo.filetype ~= "nix" then
    return content
  end
  
  -- Handle Nix escape sequences
  -- ''$ -> $
  content = content:gsub("''%$", "$")
  -- ''' -> ''
  content = content:gsub("'''", "''")
  -- Other escape sequences
  content = content:gsub("''\\n", "\n")
  content = content:gsub("''\\r", "\r")
  content = content:gsub("''\\t", "\t")
  
  -- Replace Nix interpolations with bash-valid placeholders
  -- This prevents LSP errors for Nix interpolations
  
  -- Strategy: Replace ${...} with placeholder values that work in context
  -- For paths: ${pkgs.curl}/bin/curl -> /nix/store/placeholder/bin/curl  
  -- For strings: "host: ${host}" -> "host: PLACEHOLDER"
  -- For values: VAR=${value} -> VAR=PLACEHOLDER
  
  -- First, handle ${...}/ patterns (path interpolations)
  content = content:gsub("%${.-}/", "/nix/store/placeholder/")
  
  -- Then handle all remaining ${...} with simple placeholders
  -- These work whether in strings, as values, or standalone
  content = content:gsub("%${.-}", "PLACEHOLDER")
  
  return content
end

-- Monkey patch otter's internal functions to preprocess content
local keeper = require("otter.keeper")
local original_extract = keeper.extract_code_chunks

keeper.extract_code_chunks = function(bufnr, lang, query)
  local chunks = original_extract(bufnr, lang, query)
  
  -- Only process if we're in a Nix file
  if vim.bo[bufnr].filetype == "nix" then
    -- chunks is organized by language, not a simple array
    for lang_name, lang_chunks in pairs(chunks) do
      for _, chunk in ipairs(lang_chunks) do
        -- Apply preprocessing to remove Nix escape sequences
        local processed_lines = {}
        for _, line in ipairs(chunk.text) do
          table.insert(processed_lines, preprocess_nix_escapes(line))
        end
        chunk.text = processed_lines
      end
    end
  end
  
  return chunks
end

otter.setup({
  lsp = {
    diagnostic_update_events = { "BufWritePost", "InsertLeave", "TextChanged" },
  },
  -- Don't strip quotes since we're handling magic comments
  strip_wrapping_quote_characters = {},
})

-- Auto-activate otter for Nix files
vim.api.nvim_create_autocmd("FileType", {
  pattern = "nix",
  callback = function()
    -- Small delay to ensure buffer is ready
    vim.defer_fn(function()
      -- Activate with common embedded languages in Nix files
      otter.activate({ "bash", "lua", "python", "javascript", "typescript" })
    end, 100)
  end,
})

-- Manual activation command for testing
vim.api.nvim_create_user_command("OtterActivate", function()
  otter.activate({ "bash", "lua", "python", "javascript", "typescript" })
  vim.notify("Otter activated")
end, {})

-- Command to show what otter sees after preprocessing
vim.api.nvim_create_user_command("OtterShowPreprocessed", function()
  local bufnr = vim.api.nvim_get_current_buf()
  if vim.bo[bufnr].filetype ~= "nix" then
    vim.notify("This command only works in Nix files", vim.log.levels.WARN)
    return
  end
  
  -- Get the current line
  local line = vim.api.nvim_get_current_line()
  local processed = preprocess_nix_escapes(line)
  
  if line ~= processed then
    vim.notify("Original: " .. line .. "\nOtter sees: " .. processed, vim.log.levels.INFO)
  else
    vim.notify("No preprocessing needed for this line", vim.log.levels.INFO)
  end
end, { desc = "Show how otter preprocesses the current line" })
