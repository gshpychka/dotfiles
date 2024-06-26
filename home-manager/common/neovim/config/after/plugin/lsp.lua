function CreateOpts(bufnr, description)
	return {
		buffer = bufnr,
		remap = false,
		desc = description,
	}
end

local on_attach = function(client, bufnr)
	local function createOpts(description)
		return CreateOpts(bufnr, description)
	end

	-- Mappings.
	-- See `:help vim.diagnostic.*` for documentation on any of the below functions
	vim.keymap.set("n", "<leader>e", function()
		vim.diagnostic.open_float()
	end, createOpts("Open LSP diagnostics float"))
	vim.keymap.set("n", "[d", function()
		vim.diagnostic.goto_prev({ _highest = true })
	end, createOpts("Go to previous LSP diagnostic"))
	vim.keymap.set("n", "]d", function()
		vim.diagnostic.goto_next({ _highest = true })
	end, createOpts("Go to next LSP diagnostic"))
	vim.keymap.set("n", "gd", function()
		vim.lsp.buf.definition()
	end, createOpts("Go to definition"))
	vim.keymap.set("n", "gD", function()
		vim.lsp.buf.type_definition()
	end, createOpts("Go to the type definition"))
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
	vim.keymap.set("n", "<leader>rn", ":IncRename ", createOpts("LSP rename"))
	vim.keymap.set("n", "<leader>cda", function()
		vim.lsp.buf.code_action()
	end, createOpts("LSP code action"))
	vim.keymap.set("n", "<leader>fo", function()
		vim.lsp.buf.format({ timeout_ms = 5000 })
	end, createOpts("LSP format"))
	vim.keymap.set("n", "<leader>il", function()
		vim.lsp.inlay_hint.enable(
			not vim.lsp.inlay_hint.is_enabled({ bufnr = bufnr })
		)
	end, createOpts("Toggle LSP inlay hints"))

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

	vim.api.nvim_create_autocmd({ "BufWritePre" }, {
		buffer = bufnr,
		callback = function()
			if client.server_capabilities.documentFormattingProvider then
				vim.lsp.buf.format({ timeout_ms = 5000 })
			end
		end,
	})
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
			vim.diagnostic.open_float({
				severity_sort = true,
				focusable = false,
			})
		end,
	})
	vim.lsp.handlers["textDocument/publishDiagnostics"] =
		vim.lsp.with(vim.lsp.diagnostic.on_publish_diagnostics, {
			virtual_text = {
				prefix = "",
			},
			severity_sort = true,
			underline = true,
			signs = true,
		})
end

-- LSP servers

local capabilities = require("cmp_nvim_lsp").default_capabilities()

require("lspconfig").pyright.setup({
	capabilities = capabilities,
})

require("typescript-tools").setup({
	on_attach = function(client, bufnr)
		-- Formatting is handled by eslint via its LSP server
		client.server_capabilities.documentFormattingProvider = nil
		client.server_capabilities.documentRangeFormattingProvider = nil
		on_attach(client, bufnr)
	end,
	capabilities = capabilities,
	settings = {
		tsserver_file_preferences = {
			includeInlayParameterNameHints = "all",
			includeInlayParameterNameHintsWhenArgumentMatchesName = true,
			includeInlayFunctionParameterTypeHints = true,
			includeInlayVariableTypeHints = true,
			includeInlayPropertyDeclarationTypeHints = true,
			includeInlayFunctionLikeReturnTypeHints = true,
			includeInlayEnumMemberValueHints = true,
			-- TODO: revisit
			importModuleSpecifierPreference = "relative",
		},
	},
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
				checkThirdParty = true,
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
					autoEvalInputs = false,
				},
			},
		},
	},
})

require("lspconfig").eslint.setup({
	settings = {
		workingDirectory = { mode = "auto" },
	},
})

require("lspconfig").zls.setup({})

local null_ls = require("null-ls")
null_ls.setup({
	debug = true,
	sources = {
		null_ls.builtins.diagnostics.flake8,
		null_ls.builtins.diagnostics.jsonlint,
		null_ls.builtins.formatting.fixjson,
		null_ls.builtins.formatting.autopep8,
		null_ls.builtins.formatting.isort,
		null_ls.builtins.formatting.black,
		null_ls.builtins.formatting.alejandra,
		null_ls.builtins.formatting.stylua,
		null_ls.builtins.formatting.yamlfmt.with({
			extra_args = {
				"-formatter",
				"retain_line_breaks_single=true,max_line_length=120",
				"-continue_on_error",
				"true",
			},
		}),
	},
	on_attach = on_attach,
})

require("inc_rename").setup({})
