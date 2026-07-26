-- Mason packages that are not language servers: formatters and linters.
--
-- Kept in its own module, alongside config/servers.lua, so install.sh can
-- pre-install them during setup instead of leaving the first edit to do it.
return {
  "prettierd",
  "ruff",
  -- bashls picks shellcheck up automatically when it is on $PATH.
  "shellcheck",
  "shfmt",
  "stylua",
  "taplo",
}
