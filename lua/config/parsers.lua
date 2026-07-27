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
---@return integer installed, integer wanted, string|nil error, string[] missing
function M.ensure(opts)
  opts = opts or {}

  local ok, nts = pcall(require, "nvim-treesitter")
  if not ok then
    return 0, #M.parsers, "nvim-treesitter is not available", vim.deepcopy(M.parsers)
  end

  -- Count only the parsers this config asks for. get_installed() also reports
  -- parsers nvim-treesitter pulled in as dependencies -- `xml` drags in `dtd` --
  -- so a bare count of it can equal #M.parsers while a wanted parser is absent.
  -- That is not hypothetical: a Fedora install reported "26/26 installed" with
  -- `dtd` present and `vimdoc` missing, and a Debian one reported "27/26".
  local function missing_parsers()
    local installed = {}
    for _, name in ipairs(nts.get_installed("parsers") or {}) do
      installed[name] = true
    end
    return vim.tbl_filter(function(name) return not installed[name] end, M.parsers)
  end

  local function report(err)
    local missing = missing_parsers()
    return #M.parsers - #missing, #M.parsers, err, missing
  end

  if #missing_parsers() == 0 then
    return report(nil)
  end

  if not ensure_cli() then
    return report(("tree-sitter CLI not found; run `npm install` in %s"):format(vim.fn.stdpath("config")))
  end

  -- Deliberately just the batch and its handle -- see the treesitter notes in
  -- CLAUDE.md. nvim-treesitter drops one to three parsers out of a 26-parser
  -- batch and resolves the handle anyway, and neither polling the wanted set
  -- nor reinstalling the shortfall fixed it here: polling to completion stalls
  -- for the whole budget, and a retry loop with stall detection measured
  -- *worse*, 3/26, because it cuts into compiles that were still progressing.
  -- So report the shortfall honestly; install.sh calls ensure() twice, which is
  -- what actually gets all 26 in place.
  local done, err = pcall(function()
    local handle = nts.install(missing_parsers())
    if opts.timeout_ms and handle and handle.wait then
      handle:wait(opts.timeout_ms)
    end
  end)

  return report((not done) and tostring(err) or nil)
end

return M
