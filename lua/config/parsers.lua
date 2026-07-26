-- Treesitter parsers, and the filetypes highlighting is started for.
--
-- Kept in its own module so install.sh can install the parsers during setup.
-- lazy.nvim's `build` step alone is not enough: it only runs when the plugin
-- itself is installed or updated, so adding a parser to this list would never
-- fetch it.
return {
  parsers = {
    "bash",
    "css",
    "diff",
    "dockerfile",
    "git_config",
    "git_rebase",
    "gitcommit",
    "gitignore",
    "html",
    "javascript",
    "jsdoc",
    "json",
    -- No jsonc parser exists upstream; Neovim maps the jsonc filetype onto the
    -- json parser, so highlighting still works for .jsonc files.
    "lua",
    "luadoc",
    "markdown",
    "markdown_inline",
    "python",
    "query",
    "regex",
    "scss",
    "sql",
    "toml",
    "vim",
    "vimdoc",
    "xml",
    "yaml",
  },

  filetypes = {
    "css",
    "diff",
    "dockerfile",
    "gitcommit",
    "gitconfig",
    "gitignore",
    "gitrebase",
    "html",
    "javascript",
    "javascriptreact",
    "json",
    "jsonc",
    "lua",
    "markdown",
    "python",
    "query",
    "scss",
    "sh",
    "sql",
    "toml",
    "vim",
    "vimdoc",
    "xml",
    "yaml",
  },
}
