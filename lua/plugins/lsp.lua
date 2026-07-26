local lsp = require("config.lsp")

local servers = {
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
  -- The interpreter is set at runtime by lua/config/python.lua, which detects
  -- the project virtualenv; without it every third-party import is unresolved.
  --
  -- Note: pyright does not implement textDocument/inlayHint, so the inlayHints
  -- settings below are inert. Swap the key to `basedpyright` (a drop-in fork)
  -- if you want Python inlay hints.
  pyright = {
    settings = {
      python = {
        analysis = {
          autoSearchPaths = true,
          diagnosticMode = "workspace",
          useLibraryCodeForTypes = true,
          inlayHints = {
            variableTypes = true,
            functionReturnTypes = true,
            callArgumentNames = true,
          },
        },
      },
    },
  },
  ruff = {},
  yamlls = {},
}

return {
  {
    "mason-org/mason.nvim",
    opts = {},
  },
  {
    "mason-org/mason-lspconfig.nvim",
    opts = {
      ensure_installed = vim.tbl_keys(servers),
    },
    dependencies = {
      "mason-org/mason.nvim",
      "neovim/nvim-lspconfig",
      "saghen/blink.cmp",
    },
    config = function(_, opts)
      for name, config in pairs(servers) do
        vim.lsp.config(name, vim.tbl_deep_extend("force", {
          capabilities = lsp.capabilities(),
        }, config))
      end

      require("mason-lspconfig").setup(opts)
    end,
  },
}
