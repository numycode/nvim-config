-- Shared state for the live preview: the statusline button in lua/plugins/ui.lua
-- and the <leader>p keymaps in lua/plugins/webpreview.lua both go through here,
-- so "is it running" and "can this buffer be previewed" have one answer.
local M = {}

-- Also handed to the plugin in webpreview.lua, so the number in the button label
-- and the number the server binds cannot drift apart.
M.port = 5500

-- The rule live-preview.nvim itself uses to decide what it can serve
-- (livepreview/utils.lua, `supported_filetype`). It matches on the *filename*,
-- not on `&filetype`, and the difference is not academic: a `.htm` file gets
-- `filetype=html` but fails the plugin's `%.html$`, so gating the button on the
-- filetype would offer a button that, once clicked, silently previews whichever
-- other buffer `find_supported_buf()` stumbles on. Better to show no button.
local EXTENSIONS = { "%.html$", "%.md$", "%.markdown$", "%.adoc$", "%.asciidoc$", "%.svg$" }

--- Whether the current buffer is one the preview server can serve.
--- Called from a lualine `cond`, so it must stay a name lookup and a few pattern
--- matches -- no shelling out, no plugin loading.
function M.previewable()
  if vim.bo.buftype ~= "" then
    return false
  end

  local name = vim.api.nvim_buf_get_name(0)

  for _, pattern in ipairs(EXTENSIONS) do
    if name:match(pattern) then
      return true
    end
  end

  return false
end

--- Whether the preview server is up.
--- Reads `package.loaded` rather than require()ing, the same way the wakatime
--- component in ui.lua does: a require() here would pull the plugin in on the
--- first redraw and defeat its `cmd = "LivePreview"` lazy-loading. Once loaded,
--- `is_running()` is two table field reads -- no syscall, legal in a render path.
function M.running()
  local livepreview = package.loaded.livepreview

  return livepreview ~= nil and livepreview.is_running()
end

--- Throw away the plugin's wedged server state, so the next start can succeed.
---
--- Works around an upstream bug that only exists on Linux. `Watcher:close()`
--- (server/fswatch.lua:102) does a bare `self.watcher:close()`, but `Watcher:start()`
--- sets `self.watcher = nil` when the directory it was watching disappears -- so
--- once any watched directory is deleted, `close()` throws. Everything after the
--- throw is skipped: `Server:stop` never nils `_watcher` nor deletes its augroup,
--- and `livepreview.close()` never nils `serverObj`. Since `start()` calls
--- `close()` first, the next start throws too, and the preview is dead for the
--- rest of the session -- measured, `LivePreview start` failing with "handle
--- 0x... is already closing" at the same line.
---
--- This is not exotic. The watcher tree covers `.git` (upstream's `subdir ~= ".git"`
--- guard compares a *full path* against the bare string, so it never matches), and
--- a plain `git gc` deletes the loose-object directories: measured, `git gc
--- --prune=now` in a two-commit repo removed 6 directories under `.git/objects`
--- and wedged the preview exactly as deleting a source folder does.
---
--- Clearing `serverObj` is what makes recovery work -- verified end to end, not
--- just by is_running(): after the reset a restart bound the port, completed a
--- websocket handshake, and delivered a real `{"type":"reload"}` frame on the next
--- write. It also defuses the plugin's own VimLeavePre handler, which bails out
--- early when `serverObj` is nil rather than throwing on the way out.
local function reset_wedged_state()
  local livepreview = package.loaded.livepreview

  if livepreview then
    livepreview.serverObj = nil
  end

  -- `Server:stop` deletes this itself, on the line after the one that throws.
  pcall(vim.api.nvim_del_augroup_by_name, "LivePreview")
end

--- Start the server on the current buffer.
--- Goes through the user command rather than the Lua API on purpose: the command
--- body is where upstream resolves the buffer, computes the URL relative to the
--- webroot, encodes it and opens the browser. `M.start()` alone does none of that.
---
--- `silent` is not cosmetic. The command ends in `print("... Opening browser at
--- <url>")`, and that leaves a "Press ENTER or type command to continue" prompt
--- which blocks the event loop until it is dismissed -- measured on an 80-column
--- terminal, from the button, with the server already started behind the prompt.
--- Clicking a button and having the editor freeze is the worst version of this
--- feature. It suppresses only those two `print`s; the plugin's real failures go
--- through vim.notify, which `silent` does not touch. The state they announced is
--- in the button anyway.
---
--- The retry is deliberately the only thing wrapped: a second failure is a real
--- one and is left to surface.
function M.start()
  if pcall(vim.cmd, "silent LivePreview start") then
    return
  end

  reset_wedged_state()
  vim.cmd("silent LivePreview start")
end

--- Stop the server, surviving the fswatch bug above.
function M.stop()
  if not pcall(vim.cmd, "silent LivePreview close") then
    reset_wedged_state()
  end
end

--- Start the server on the current buffer, or stop it if it is already up.
function M.toggle()
  if M.running() then
    M.stop()
  else
    M.start()
  end
end

return M
