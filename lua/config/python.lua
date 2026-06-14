local function project_root()
  return vim.fs.root(0, { "pyproject.toml", "uv.lock", ".git" }) or vim.fn.getcwd()
end

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

vim.api.nvim_create_user_command("UvSync", function()
  run_async({ "uv", "sync" }, "uv sync")
end, {
  desc = "Sync the current Python project with uv",
})

vim.api.nvim_create_user_command("RuffCheck", function()
  local executable = vim.fn.executable("ruff") == 1 and { "ruff", "check", "." }
    or { "uvx", "ruff", "check", "." }

  run_async(executable, "ruff check")
end, {
  desc = "Run Ruff in the current Python project",
})
