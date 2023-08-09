local on_attach = function(client, bufnr)
	local function createOpts(description)
		return {
			buffer = bufnr,
			remap = false,
			desc = description,
		}
	end

	-- Mappings.
	-- See `:help vim.diagnostic.*` for documentation on any of the below functions
	vim.keymap.set("n", "<leader>e", function()
		vim.diagnostic.open_float()
	end, createOpts("Open LSP diagnostics float"))
	vim.keymap.set("n", "[d", function()
		vim.diagnostic.goto_prev()
	end, createOpts("Go to previous LSP diagnostic"))
	vim.keymap.set("n", "]d", function()
		vim.diagnostic.goto_next()
	end, createOpts("Go to next LSP diagnostic"))
	vim.keymap.set("n", "gd", function()
		vim.lsp.buf.definition()
	end, createOpts("Go to definition"))
	vim.keymap.set("n", "gi", function()
		vim.lsp.buf.implementation()
	end, createOpts("Go to implementation"))
	vim.keymap.set("n", "gr", function()
		vim.lsp.buf.references()
	end, createOpts("Go to references"))
	vim.keymap.set("n", "K", function()
		vim.lsp.buf.hover()
	end, createOpts("LSP hover"))
	vim.keymap.set({ "n", "i" }, "<C-s>", function()
		vim.lsp.buf.signature_help()
	end, createOpts("Signature help"))
	vim.keymap.set("n", "<leader>wa", function()
		vim.lsp.buf.add_workspace_folder()
	end, createOpts("Add workspace folder"))
	vim.keymap.set("n", "<leader>wr", function()
		vim.lsp.buf.remove_workspace_folder()
	end, createOpts("Remove workspace folder"))
	vim.keymap.set("n", "<leader>D", function()
		vim.lsp.buf.type_definition()
	end, createOpts("Go to the type definition"))
	vim.keymap.set("n", "<leader>rn", function()
		vim.lsp.buf.rename()
	end, createOpts("LSP rename"))
	vim.keymap.set("n", "<leader>ca", function()
		vim.lsp.buf.code_action()
	end, createOpts("LSP code action"))
	vim.keymap.set("n", "<leader>fo", function()
		vim.lsp.buf.format()
	end, createOpts("LSP format"))

	-- Set autocommands conditional on server_capabilities
	if client.server_capabilities.documentHighlightProvider then
		local group = vim.api.nvim_create_augroup("LSPDocumentHighlight", {})
		vim.api.nvim_create_autocmd({ "CursorHold" }, {
			buffer = bufnr,
			group = group,
			callback = function()
				vim.lsp.buf.document_highlight()
			end,
		})
		vim.api.nvim_create_autocmd({ "CursorMoved" }, {
			buffer = bufnr,
			group = group,
			callback = function()
				vim.lsp.buf.clear_references()
			end,
		})
	end
	-- if client.server_capabilities.signatureHelpProvider then
	--     vim.api.nvim_create_autocmd({ "CursorHoldI" }, {
	--         buffer=bufnr,
	--         callback = function()
	--             vim.lsp.buf.signature_help()
	--         end,
	--     })
	-- end
	vim.api.nvim_create_autocmd({ "CursorHold" }, {
		buffer = bufnr,
		callback = function()
			vim.diagnostic.open_float(0, { focusable = false })
		end,
	})
	vim.lsp.handlers["textDocument/publishDiagnostics"] = vim.lsp.with(vim.lsp.diagnostic.on_publish_diagnostics, {
		virtual_text = {
			prefix = "",
		},
		severity_sort = true,
		underline = true,
		signs = true,
	})
end

-- lightbulb if code action available
require("nvim-lightbulb").setup()

-- Completions

local has_words_before = function()
	unpack = unpack or table.unpack
	local line, col = unpack(vim.api.nvim_win_get_cursor(0))
	return col ~= 0 and vim.api.nvim_buf_get_lines(0, line - 1, line, true)[1]:sub(col, col):match("%s") == nil
end

local cmp = require("cmp")
local luasnip = require("luasnip")

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
					cmp.confirm({ behavior = cmp.ConfirmBehavior.Replace, select = false })
				else
					fallback()
				end
			end,
			s = cmp.mapping.confirm({ select = true }),
			c = cmp.mapping.confirm({ behavior = cmp.ConfirmBehavior.Replace, select = true }),
		}),
		-- https://github.com/hrsh7th/nvim-cmp/wiki/Example-mappings#luasnip
		["<Tab>"] = cmp.mapping(function(fallback)
			if cmp.visible() then
				cmp.select_next_item()
				-- You could replace the expand_or_jumpable() calls with expand_or_locally_jumpable()
				-- they way you will only jump inside the snippet region
			elseif luasnip.expand_or_jumpable() then
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
		{ name = "nvim_lsp", group_index = 2 },
		-- { name = "copilot",  group_index = 2 },
		-- { name = 'luasnip' }, -- For luasnip users.
	}),
})

cmp.setup.filetype("lua", {
	sources = cmp.config.sources({
		{ name = "cmp-nvim-lua", group_index = 2 },
		{ name = "nvim_lsp", group_index = 2 },
		-- { name = "copilot",      group_index = 2 },
	}),
})

-- LSP servers

local capabilities = require("cmp_nvim_lsp").default_capabilities()

require("lspconfig").pyright.setup({
	on_attach = function(client, bufnr)
		on_attach(client, bufnr)
	end,
	capabilities = capabilities,
	-- settings = {
	--     python = {
	--         analysis = {
	--             -- stubPath = "/home/gshpychka/venvs/.typestubs",
	--             useLibraryCodeForTypes = false,
	--             diagnosticMode = "openFilesOnly",
	--             -- autoSearchPaths = false,
	--             typeCheckingMode = "basic",
	--             reportMissingTypeStubs = false,
	--             diagnosticSeverityOverrides = {
	--                 reportUninitializedInstanceVariable = "warning",
	--                 reportMissingImports = "error",
	--                 reportImportCycles = "warning",
	--                 reportDuplicateImport = "info",
	--                 reportOverlappingOverload = "warning",
	--                 reportIncompatibleMethodOverride = "warning",
	--                 reportIncompatibleVariableOverride = "warning",
	--                 strictParameterNoneValue = "info",
	--                 strictListInference = true,
	--                 strictDictionaryInference = true,
	--                 strictSetInference = true,
	--                 reportUnnecessaryCast = "info",
	--                 reportUnnecessaryComparison = "info",
	--                 reportUnnecessaryIsInstance = "info",
	--                 reportUnnecessaryTypeIgnoreComment = "info",
	--                 reportImplicitStringConcatenation = "warning",
	--                 reportCallInDefaultInitializer = "error",
	--                 reportPropertyTypeMismatch = "warning",
	--                 reportUntypedFunctionDecorator = "info",
	--                 reportUntypedClassDecorator = "info",
	--                 reportUntypedBaseClass = "info",
	--                 reportPrivateUsage = "warning",
	--                 reportConstantRedefinition = "warning",
	--                 reportMissingSuperCall = "warning",
	--                 reportUnknownParameterType = "none",
	--                 reportUnknownArgumentType = "none",
	--                 reportUnknownVariableType = "none",
	--                 reportUnknownMemberType = "none",
	--                 reportMissingParameterType = "none",
	--                 reportMissingTypeArgument = "none",
	--                 reportUnusedVariable = "info",
	--             }
	--         }
	--     }
	-- }
})

require("lspconfig").tsserver.setup({
	capabilities = capabilities,
	on_attach = function(client, bufnr)
		client.server_capabilities.document_formatting = false
		client.server_capabilities.document_range_formatting = false

		local ts_utils = require("nvim-lsp-ts-utils")
		ts_utils.setup({})
		ts_utils.setup_client(client)

		-- buf_map(bufnr, "n", "gs", ":TSLspOrganize<CR>")
		-- buf_map(bufnr, "n", "gi", ":TSLspRenameFile<CR>")
		-- buf_map(bufnr, "n", "go", ":TSLspImportAll<CR>")

		on_attach(client, bufnr)
	end,
})

require("lspconfig").lua_ls.setup({
	capabilities = capabilities,
	on_attach = on_attach,
	settings = {
		Lua = {
			runtime = {
				-- Tell the language server which version of Lua you're using (most likely LuaJIT in the case of Neovim)
				version = "LuaJIT",
			},
			diagnostics = {
				-- Get the language server to recognize the `vim` global
				globals = { "vim" },
			},
			workspace = {
				-- Make the server aware of Neovim runtime files
				library = vim.api.nvim_get_runtime_file("", true),
				checkThirdParty = false,
			},
			-- Do not send telemetry data containing a randomized but unique identifier
			telemetry = {
				enable = false,
			},
		},
	},
})

require("lspconfig").nil_ls.setup({
	capabilities = capabilities,
	on_attach = on_attach,
	settings = {
		["nil"] = {
			nix = {
				flake = {
					autoEvalInputs = true,
				},
			},
		},
	},
})

local null_ls = require("null-ls")

null_ls.setup({
	sources = {
		null_ls.builtins.code_actions.eslint_d,
		null_ls.builtins.code_actions.gitsigns,
		null_ls.builtins.code_actions.statix,
		-- null_ls.builtins.diagnostics.eslint_d,
		null_ls.builtins.diagnostics.flake8,
		null_ls.builtins.diagnostics.jsonlint,
		-- null_ls.builtins.diagnostics.mypy,
		null_ls.builtins.formatting.eslint_d,
		null_ls.builtins.formatting.fixjson,
		null_ls.builtins.formatting.black,
		null_ls.builtins.formatting.autoflake,
		null_ls.builtins.formatting.isort,
		null_ls.builtins.formatting.alejandra,
		null_ls.builtins.formatting.stylua,
		null_ls.builtins.formatting.yamlfmt,
	},
	on_attach = on_attach,
})

LaunchWing = function()
	local client_id = vim.lsp.start_client({ cmd = { "wing", "lsp" } })
	vim.lsp.buf_attach_client(0, client_id)
end

vim.cmd([[
	command! -range LaunchWing execute 'lua LaunchWing()'
]])
