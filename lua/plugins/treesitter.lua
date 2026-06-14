{
  "nvim-treesitter/nvim-treesitter",
  build = ":TSUpdate",      -- update parsers
  opts = {
    ensure_installed = {"python", "html", "css", "lua", "json", "yaml"},
    highlight = { enable = true },
    indent = { enable = true },
  },
  config = function(_, opts)
    require("nvim-treesitter.configs").setup(opts)
  end,
}
