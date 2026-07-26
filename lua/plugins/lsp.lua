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

return {
  {
    "mason-org/mason.nvim",
    cmd = {
      "Mason",
      "MasonInstall",
      "MasonLog",
      "MasonUninstall",
      "MasonUninstallAll",
      "MasonUpdate",
    },
    opts = {},
  },
  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = { "mason-org/mason.nvim" },
    opts = {
      ensure_installed = {
        "prettierd",
        "ruff",
        -- bashls picks shellcheck up automatically when it is on $PATH.
        "shellcheck",
        "shfmt",
        "stylua",
        "taplo",
      },
      run_on_start = true,
    },
  },
  {
    "mason-org/mason-lspconfig.nvim",
    -- Deferred to the first real buffer so that bare `nvim` (the dashboard)
    -- never pays for the LSP chain, which drags in blink.cmp and LuaSnip.
    event = { "BufReadPre", "BufNewFile" },
    opts = {
      ensure_installed = vim.tbl_keys(servers),
      -- Enable exactly the servers in the table above. With the default
      -- (automatic_enable = true) any server left installed in Mason attaches
      -- too, so removing one here would not actually stop it running.
      automatic_enable = false,
    },
    dependencies = {
      "mason-org/mason.nvim",
      "neovim/nvim-lspconfig",
      "saghen/blink.cmp",
    },
    config = function(_, opts)
      local capabilities = lsp.capabilities()

      for name, config in pairs(servers) do
        vim.lsp.config(name, vim.tbl_deep_extend("force", { capabilities = capabilities }, config))
      end

      require("mason-lspconfig").setup(opts)
      vim.lsp.enable(vim.tbl_keys(servers))
    end,
  },
}
