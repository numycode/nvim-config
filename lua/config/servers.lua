-- Language servers, keyed by lspconfig name, with their settings.
-- Kept in its own module so install.sh can enumerate them and pre-install the
-- matching Mason packages during setup, rather than leaving the first real edit
-- to download them.
return {
  bashls = {},
  cssls = {},
  html = {},
  jsonls = {},
  -- Attaches only when the project actually has an ESLint config.
  eslint = {},
  marksman = {},
  taplo = {},
  -- Emmet abbreviation expansion (div.foo>ul>li*3) in markup and JSX.
  emmet_language_server = {
    filetypes = { "html", "css", "scss", "javascriptreact" },
  },
  -- Named "ts_ls" but it is also *the* language server for plain JavaScript.
  -- Restricted to JS filetypes so it never attaches to TypeScript.
  ts_ls = {
    filetypes = { "javascript", "javascriptreact" },
    settings = {
      javascript = {
        inlayHints = {
          includeInlayEnumMemberValueHints = true,
          includeInlayFunctionLikeReturnTypeHints = true,
          includeInlayFunctionParameterTypeHints = true,
          includeInlayParameterNameHints = "all",
          includeInlayParameterNameHintsWhenArgumentMatchesName = false,
          includeInlayPropertyDeclarationTypeHints = true,
          includeInlayVariableTypeHints = true,
        },
      },
    },
  },
  lua_ls = {
    settings = {
      Lua = {
        runtime = {
          version = "LuaJIT",
        },
        diagnostics = {
          globals = { "vim" },
        },
        workspace = {
          checkThirdParty = false,
          library = {
            vim.env.VIMRUNTIME,
          },
        },
        hint = {
          enable = true,
          arrayIndex = "Disable",
        },
      },
    },
  },
  -- basedpyright rather than pyright: it is a drop-in fork that actually
  -- implements textDocument/inlayHint, which pyright does not.
  --
  -- The interpreter is set at runtime by lua/config/python.lua, which detects
  -- the project virtualenv; without it every third-party import is unresolved.
  basedpyright = {
    settings = {
      basedpyright = {
        analysis = {
          autoSearchPaths = true,
          diagnosticMode = "workspace",
          useLibraryCodeForTypes = true,
          -- "recommended" turns on a wall of strict-mode reporting; "standard"
          -- matches what pyright called basic.
          typeCheckingMode = "standard",
          inlayHints = {
            variableTypes = true,
            functionReturnTypes = true,
            callArgumentNames = true,
            genericTypes = false,
          },
        },
      },
    },
  },
  ruff = {},
  yamlls = {},
}
