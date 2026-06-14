return {
  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    dependencies = {
      "mason-org/mason.nvim",
    },
    opts = {
      ensure_installed = {
        "ruff",
        "shfmt",
        "stylua",
        "prettierd",
      },
      run_on_start = true,
    },
  },
}
