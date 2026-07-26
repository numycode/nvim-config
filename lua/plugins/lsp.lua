local lsp = require("config.lsp")
local servers = require("config.servers")

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
      ensure_installed = require("config.tools"),
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
