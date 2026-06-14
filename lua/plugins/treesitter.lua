local parsers = {
  "bash",
  "css",
  "html",
  "json",
  "lua",
  "markdown",
  "markdown_inline",
  "python",
  "query",
  "vim",
  "vimdoc",
  "yaml",
}

local filetypes = {
  "css",
  "html",
  "json",
  "lua",
  "markdown",
  "python",
  "query",
  "sh",
  "vim",
  "vimdoc",
  "yaml",
}

return {
  "nvim-treesitter/nvim-treesitter",
  lazy = false,
  build = function()
    local config_dir = vim.fs.normalize(vim.fn.stdpath("config"))
    local local_cli = vim.fs.joinpath(config_dir, "node_modules", "tree-sitter-cli", "tree-sitter")

    if vim.fn.executable("tree-sitter") == 0 and vim.fn.filereadable(local_cli) == 1 then
      vim.env.PATH = vim.fs.dirname(local_cli) .. ":" .. vim.env.PATH
    end

    if vim.fn.executable("tree-sitter") == 0 then
      vim.notify("tree-sitter CLI not found; skipping parser installation", vim.log.levels.WARN)
      return
    end

    require("nvim-treesitter").install(parsers):wait(300000)
  end,
  opts = {
    filetypes = filetypes,
  },
  config = function(_, opts)
    require("nvim-treesitter").setup()

    vim.api.nvim_create_autocmd("FileType", {
      group = vim.api.nvim_create_augroup("treesitter_start", { clear = true }),
      pattern = opts.filetypes,
      callback = function()
        pcall(vim.treesitter.start)
      end,
    })

    vim.api.nvim_create_autocmd("FileType", {
      group = vim.api.nvim_create_augroup("treesitter_indent", { clear = true }),
      pattern = opts.filetypes,
      callback = function()
        vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
      end,
    })
  end,
}
