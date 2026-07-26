return {
  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    dependencies = {
      "mason-org/mason.nvim",
    },
    opts = {
      ensure_installed = {
        "markdownlint-cli2",
        "prettierd",
        "ruff",
        "shellcheck",
        "shfmt",
        "stylua",
      },
      run_on_start = true,
    },
  },
}
