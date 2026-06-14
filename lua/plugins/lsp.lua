local lsp = require("config.lsp")

local servers = {
  bashls = {},
  cssls = {},
  html = {},
  jsonls = {},
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
      },
    },
  },
  pyright = {
    settings = {
      python = {
        analysis = {
          autoSearchPaths = true,
          diagnosticMode = "workspace",
          useLibraryCodeForTypes = true,
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
      "hrsh7th/cmp-nvim-lsp",
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
