local M = {}

function M.capabilities()
  local ok, blink = pcall(require, "blink.cmp")

  if ok then
    return blink.get_lsp_capabilities()
  end

  return vim.lsp.protocol.make_client_capabilities()
end

-- Prefer the snacks picker for LSP navigation; fall back to the built-in
-- handler so these keymaps still work if snacks fails to load.
local function pick(source, fallback)
  return function()
    local ok, snacks = pcall(require, "snacks")

    if ok and snacks.picker then
      return snacks.picker[source]()
    end

    return fallback()
  end
end

function M.on_attach(client, bufnr)
  local map = function(mode, lhs, rhs, desc, method)
    -- Skip keymaps the attached server cannot service.
    if method and client and not client:supports_method(method) then
      return
    end

    vim.keymap.set(mode, lhs, rhs, {
      buffer = bufnr,
      silent = true,
      desc = desc,
    })
  end

  local methods = vim.lsp.protocol.Methods

  -- Navigation
  map("n", "gd", pick("lsp_definitions", vim.lsp.buf.definition), "Goto definition", methods.textDocument_definition)
  map("n", "gD", pick("lsp_declarations", vim.lsp.buf.declaration), "Goto declaration", methods.textDocument_declaration)
  map("n", "gr", pick("lsp_references", vim.lsp.buf.references), "References", methods.textDocument_references)
  map(
    "n",
    "gI",
    pick("lsp_implementations", vim.lsp.buf.implementation),
    "Goto implementation",
    methods.textDocument_implementation
  )
  map(
    "n",
    "gy",
    pick("lsp_type_definitions", vim.lsp.buf.type_definition),
    "Goto type definition",
    methods.textDocument_typeDefinition
  )

  -- Documentation
  map("n", "K", vim.lsp.buf.hover, "Hover documentation", methods.textDocument_hover)
  map("n", "gK", vim.lsp.buf.signature_help, "Signature help", methods.textDocument_signatureHelp)
  map("i", "<C-k>", vim.lsp.buf.signature_help, "Signature help", methods.textDocument_signatureHelp)

  -- Code actions and refactoring
  map({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, "Code action", methods.textDocument_codeAction)
  map("n", "<leader>cr", vim.lsp.buf.rename, "Rename symbol", methods.textDocument_rename)
  map("n", "<leader>rn", vim.lsp.buf.rename, "Rename symbol", methods.textDocument_rename)
  map("n", "<leader>cR", function()
    require("snacks").rename.rename_file()
  end, "Rename file")

  -- Symbols
  map(
    "n",
    "<leader>cs",
    pick("lsp_symbols", vim.lsp.buf.document_symbol),
    "Document symbols",
    methods.textDocument_documentSymbol
  )
  map(
    "n",
    "<leader>cS",
    pick("lsp_workspace_symbols", vim.lsp.buf.workspace_symbol),
    "Workspace symbols",
    methods.workspace_symbol
  )

  -- Inlay hints, on by default like JetBrains. Toggle with <leader>uh.
  if client and client:supports_method(methods.textDocument_inlayHint) then
    vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
  end
end

return M
