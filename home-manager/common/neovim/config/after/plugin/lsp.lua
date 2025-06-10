require("lsp")
local ok, languages = pcall(require, "lsp.languages")
if not ok then
  languages = {}
end
for _, lang in ipairs(languages) do
  pcall(require, "lsp." .. lang)
end
