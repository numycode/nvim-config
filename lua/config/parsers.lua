-- Treesitter parsers, and the filetypes highlighting is started for.
--
-- Also owns parser installation, so lua/plugins/treesitter.lua (async, at
-- startup) and install.sh (synchronous, during setup) share one code path.
-- lazy.nvim's `build` step is not enough on its own: it only runs when the
-- plugin itself is installed or updated, so adding a parser to this list would
-- never fetch it.
local M = {}

M.parsers = {
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
}

M.filetypes = {
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
}

--- Put the vendored tree-sitter CLI on PATH when there is no system one.
---@return boolean available
local function ensure_cli()
  if vim.fn.executable("tree-sitter") == 1 then
    return true
  end

  local local_cli =
    vim.fs.joinpath(vim.fs.normalize(vim.fn.stdpath("config")), "node_modules", "tree-sitter-cli", "tree-sitter")

  if vim.fn.filereadable(local_cli) == 1 then
    vim.env.PATH = vim.fs.dirname(local_cli) .. ":" .. vim.env.PATH
  end

  return vim.fn.executable("tree-sitter") == 1
end

--- Install any parser that is not already on disk.
---@param opts? { timeout_ms?: integer } when timeout_ms is set, block until done
---@return integer installed, integer wanted, string|nil error
function M.ensure(opts)
  opts = opts or {}

  local ok, nts = pcall(require, "nvim-treesitter")
  if not ok then
    return 0, #M.parsers, "nvim-treesitter is not available"
  end

  local function count() return #(nts.get_installed("parsers") or {}) end

  local installed = {}
  for _, name in ipairs(nts.get_installed("parsers") or {}) do
    installed[name] = true
  end

  local missing = vim.tbl_filter(function(name) return not installed[name] end, M.parsers)

  if #missing == 0 then
    return count(), #M.parsers, nil
  end

  if not ensure_cli() then
    return count(), #M.parsers, ("tree-sitter CLI not found; run `npm install` in %s"):format(vim.fn.stdpath("config"))
  end

  local done, err = pcall(function()
    local handle = nts.install(missing)
    if opts.timeout_ms and handle and handle.wait then
      handle:wait(opts.timeout_ms)
    end
  end)

  return count(), #M.parsers, (not done) and tostring(err) or nil
end

return M
