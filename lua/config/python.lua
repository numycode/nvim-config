local M = {}

local function project_root() return vim.fs.root(0, { "pyproject.toml", "uv.lock", ".git" }) or vim.fn.getcwd() end

local function run_async(cmd, desc)
  vim.system(cmd, {
    cwd = project_root(),
    text = true,
  }, function(result)
    vim.schedule(function()
      if result.code == 0 then
        vim.notify(desc .. " finished", vim.log.levels.INFO)
        return
      end

      local message = result.stderr
      if message == nil or message == "" then
        message = result.stdout
      end

      vim.notify(desc .. " failed:\n" .. message, vim.log.levels.ERROR)
    end)
  end)
end

vim.api.nvim_create_user_command("UvSync", function() run_async({ "uv", "sync" }, "uv sync") end, {
  desc = "Sync the current Python project with uv",
})

vim.api.nvim_create_user_command("RuffCheck", function()
  local executable = vim.fn.executable("ruff") == 1 and { "ruff", "check", "." } or { "uvx", "ruff", "check", "." }

  run_async(executable, "ruff check")
end, {
  desc = "Run Ruff in the current Python project",
})

vim.api.nvim_create_user_command("UvAdd", function(args)
  if #args.fargs == 0 then
    vim.notify("UvAdd requires at least one package", vim.log.levels.ERROR)
    return
  end

  local cmd = { "uv", "add" }
  vim.list_extend(cmd, args.fargs)
  run_async(cmd, "uv add " .. table.concat(args.fargs, " "))
end, {
  desc = "Add a dependency with uv",
  nargs = "+",
})

vim.api.nvim_create_user_command("UvRun", function(args)
  if #args.fargs == 0 then
    vim.notify("UvRun requires a command", vim.log.levels.ERROR)
    return
  end

  local cmd = { "uv", "run" }
  vim.list_extend(cmd, args.fargs)
  run_async(cmd, "uv run " .. table.concat(args.fargs, " "))
end, {
  desc = "Run a command inside the uv environment",
  nargs = "+",
})

--- Interpreter path inside a virtualenv directory, or nil.
local function venv_python(dir)
  local candidates = {
    vim.fs.joinpath(dir, "bin", "python"),
    vim.fs.joinpath(dir, "Scripts", "python.exe"),
  }

  for _, path in ipairs(candidates) do
    if vim.fn.executable(path) == 1 then
      return path
    end
  end

  return nil
end

--- Find the interpreter for the current project.
--- Without this, pyright resolves imports against the system interpreter and
--- every third-party import shows up as unresolved.
---@return string|nil path
---@return string|nil source
function M.detect_venv()
  if vim.env.VIRTUAL_ENV then
    local python = venv_python(vim.env.VIRTUAL_ENV)
    if python then
      return python, "$VIRTUAL_ENV"
    end
  end

  local root = project_root()

  for _, name in ipairs({ ".venv", "venv", ".env" }) do
    local python = venv_python(vim.fs.joinpath(root, name))
    if python then
      return python, name
    end
  end

  return nil, nil
end

--- Point pyright at `path` and reload it, for the buffer's project.
---@param path string
function M.set_python_path(path)
  vim.g.python3_host_prog = path

  for _, client in ipairs(vim.lsp.get_clients({ name = "pyright" })) do
    client.settings = vim.tbl_deep_extend("force", client.settings or {}, {
      python = { pythonPath = path },
    })

    client:notify("workspace/didChangeConfiguration", { settings = client.settings })
  end
end

local augroup = vim.api.nvim_create_augroup("user_python", { clear = true })

vim.api.nvim_create_autocmd({ "VimEnter", "DirChanged" }, {
  group = augroup,
  desc = "Point Python tooling at the project virtualenv",
  callback = function()
    local path = M.detect_venv()
    if path then
      M.set_python_path(path)
    end
  end,
})

-- pyright may attach before or after the autocmd above has run; re-apply on
-- attach so the interpreter always sticks.
vim.api.nvim_create_autocmd("LspAttach", {
  group = augroup,
  desc = "Re-apply the project interpreter when pyright attaches",
  callback = function(event)
    local client = vim.lsp.get_client_by_id(event.data.client_id)
    if not client or client.name ~= "pyright" then
      return
    end

    local path = M.detect_venv()
    if path then
      M.set_python_path(path)
    end
  end,
})

vim.api.nvim_create_user_command("PythonVenv", function()
  local path, source = M.detect_venv()

  if not path then
    vim.notify("No virtualenv found for this project", vim.log.levels.WARN)
    return
  end

  M.set_python_path(path)
  vim.notify("Python interpreter (" .. source .. "):\n" .. path, vim.log.levels.INFO)
end, {
  desc = "Show and re-apply the detected Python interpreter",
})

vim.keymap.set("n", "<leader>cv", "<cmd>PythonVenv<CR>", {
  desc = "Python interpreter",
  silent = true,
})

return M
