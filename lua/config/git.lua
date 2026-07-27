-- Git commands that need more than a keymap can express. Loaded on demand from
-- lua/plugins/git.lua's keys and from the commit-editor autocmd in
-- lua/config/autocmds.lua -- never at startup.
local M = {}

--- Read the work tree in one shot.
---
--- Deliberately NOT require("neogit.lib.git").status.anything_staged(): that
--- shells out through neogit's runner, which outside an async context silently
--- degrades to a blocking spawn-and-wait (runner.lua:145-171), and resolving
--- `git.repo` registers a Repo instance and fires a full dispatch_refresh
--- against vim.uv.cwd() as captured at module load (repository.lua:186-198).
---
--- Also not `git diff --cached --quiet`: that exits 128 in a repo with no HEAD,
--- which reads as "something is staged" if you only test for a non-zero code.
---
--- This runs on a keypress, not on a redraw, so a bounded synchronous wait is
--- fine here -- unlike a lualine component, where it would cost ~11ms per frame.
---@return boolean? staged, boolean? unstaged, boolean? untracked
local function work_tree()
  local result = vim.system({ "git", "status", "--porcelain" }, { text = true }):wait(2000)

  if result.code ~= 0 then
    return nil
  end

  local staged, unstaged, untracked = false, false, false

  for line in (result.stdout or ""):gmatch("[^\n]+") do
    local x, y = line:sub(1, 1), line:sub(2, 2)

    if x == "?" then
      untracked = true
    else
      if x ~= " " then
        staged = true
      end
      if y ~= " " then
        unstaged = true
      end
    end
  end

  return staged, unstaged, untracked
end

--- Open neogit's commit editor, skipping the popup you would otherwise have to
--- press `c` in.
---
--- Calling neogit's commit action directly does not work, in either of the two
--- available shapes. `neogit.action("commit", "commit")()` was already measured
--- to block the event loop and open no editor (CLAUDE.md); running the same
--- action inside `require("neogit.lib.async").void(...)` -- on the theory that
--- the missing piece was the coroutine context that popup/init.lua:376 supplies
--- -- was measured here and is **no better**: it hangs Neovim outright, with the
--- editor never opening and no commit made. So the popup is not a preference,
--- it is still the only thing that works.
---
--- What is new is that the popup no longer needs a keystroke. It is a real
--- buffer with a published filetype and name (lib/popup/init.lua:418-421,
--- popups/commit/init.lua:9), so a one-shot autocmd can press `c` for you. This
--- depends on two strings, not on neogit's async internals.
function M.open_commit_editor()
  local group = vim.api.nvim_create_augroup("user_commit_popup", { clear = true })

  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = group,
    desc = "Press Commit in neogit's commit popup",
    callback = function(event)
      if
        vim.bo[event.buf].filetype ~= "NeogitPopup"
        or not vim.api.nvim_buf_get_name(event.buf):match("NeogitCommitPopup$")
      then
        return
      end

      pcall(vim.api.nvim_del_augroup_by_id, group)
      -- Scheduled, not immediate: the popup finishes wiring its own mappings
      -- after this event, and it closes itself on WinLeave (popup/init.lua:426).
      vim.schedule(function() vim.api.nvim_feedkeys("c", "m", false) end)
    end,
  })

  -- Never leave it armed. If the popup does not appear -- no repo, a lock, a
  -- neogit error -- the next unrelated buffer must not get a stray `c`.
  vim.defer_fn(function() pcall(vim.api.nvim_del_augroup_by_id, group) end, 10000)

  vim.cmd("Neogit commit")
end

--- <leader>gc. Commit, without the two dead ends neogit leaves you in.
---
--- neogit's own commit action (popups/commit/actions.lua:108-115) warns
--- "No changes to commit." and stops when nothing is staged -- uniquely among
--- its commit actions, all of which offer to stage everything first. This is
--- that escape, worded the way VSCode words it.
function M.commit()
  local staged, unstaged, untracked = work_tree()

  if staged == nil then
    vim.notify("Not a git repository.", vim.log.levels.WARN, { title = "Commit" })
    return
  end

  if not staged then
    if not unstaged and not untracked then
      vim.notify("Nothing to commit -- there are no changes.", vim.log.levels.WARN, { title = "Commit" })
      return
    end

    local choice = vim.fn.confirm(
      "There are no staged changes to commit.",
      "&Stage everything and commit\n&Open the git panel to pick\n&Cancel",
      1
    )

    if choice == 1 then
      -- -A rather than --update: --update skips new files, which is not what
      -- "everything" means to anyone coming from a graphical commit dialog.
      local added = vim.system({ "git", "add", "-A" }, { text = true }):wait(10000)

      if added.code ~= 0 then
        vim.notify("git add -A failed:\n" .. (added.stderr or ""), vim.log.levels.ERROR, { title = "Commit" })
        return
      end
    elseif choice == 2 then
      vim.cmd("Neogit")
      return
    else
      return
    end
  end

  M.open_commit_editor()
end

-- Click targets for the commit editor's winbar. A click label can only reach a
-- global function -- same constraint as _G.NvimTabline in lua/plugins/ui.lua.
_G.NvimCommit = {
  submit = function() vim.api.nvim_feedkeys(vim.keycode("ZZ"), "m", false) end,
  cancel = function() M.cancel() end,
}

--- The `q` / <leader>q / [Cancel] question.
---
--- Neogit's own `q` asks "Save changes?" with **Yes** as the default
--- (editor/init.lua:192-206 through lib/input.lua:10-16), and Yes makes the
--- commit. Measured on this config before the change: `q` then <CR> took a repo
--- from 1 commit to 2. Nobody reads "Save changes?" as "commit", so this asks
--- the real question and defaults to the harmless answer.
function M.cancel()
  local choice = vim.fn.confirm("Commit these changes?", "&Commit now\n&Discard this message\n&Keep editing", 3)

  if choice == 1 then
    vim.api.nvim_feedkeys(vim.keycode("ZZ"), "m", false)
  elseif choice == 2 then
    -- Discard is not recoverable: abort writes the buffer then sends `cq`
    -- (client.lua:88), git rewrites COMMIT_EDITMSG from the template on the next
    -- invocation, and PrevMessage reads past *commits*, not drafts. Hence the
    -- wording, and hence this not being the default.
    vim.api.nvim_feedkeys(vim.keycode("ZQ"), "m", false)
  end
end

--- Dress neogit's commit editor: a button bar it is impossible to miss, and a
--- `q` that says what it does. Called from the BufWinEnter autocmd in
--- lua/config/autocmds.lua, which is also what guarantees this runs *after*
--- neogit's own mappings -- Buffer.create sets those at lib/buffer.lua:794 and
--- only opens the window at ~806.
---@param buf integer
---@param win integer
function M.dress_commit_editor(buf, win)
  -- Window-local (the [0] scope) so it dies with the buffer and never leaks
  -- into the staged-diff split neogit opens alongside it.
  --
  -- Keys are spelled "Ctrl-S", never "<C-s>". The vim notation was measured on
  -- the owner here: the bar rendered correctly, at width 71, in a 238-column
  -- window with mouse=a, and was still read as noise -- "I typed the message but
  -- I can't figure out how to commit" while sitting in the editor with <C-s>
  -- bound in both modes. Notation is not a hint if you have to decode it.
  vim.wo[win][0].winbar = table.concat({
    "%#WinBar# ",
    "%@v:lua.NvimCommit.submit@%#DiffAdd#  ✓ Commit — press Ctrl-S  %#WinBar#%X",
    "  ",
    "%@v:lua.NvimCommit.cancel@%#DiffDelete#  ✕ Cancel — press q  %#WinBar#%X",
    -- Truncate here, not at the left edge. Without %< a narrow split drops the
    -- start of the bar -- measured at 80 columns, where it rendered as
    -- "<ss Ctrl-S   ✕ Cancel…", i.e. it ate the ✓ Commit button and kept the
    -- prose. The buttons are the part that must survive.
    "%<",
    "%#Comment#    …or click either button. Ctrl-S commits.",
  })

  for _, lhs in ipairs({ "q", "<leader>q" }) do
    vim.keymap.set("n", lhs, M.cancel, {
      buffer = buf,
      silent = true,
      desc = "Commit / discard / keep editing",
    })
  end
end

--- <leader>g?. which-key answers "what keys exist"; nothing answered "in what
--- order", which is the actual question when git is unfamiliar.
function M.cheatsheet()
  Snacks.win({
    text = {
      "# Committing, start to finish",
      "",
      "`<leader>` is the **Space** bar. So `<leader>gc` means: Space, g, c.",
      "",
      "1. `<leader>gc`  -- commit.",
      "   If you have not marked anything yet it offers to take everything,",
      "   which is usually what you want.",
      "",
      "2. Type the message in the box that opens. The diff underneath is",
      "   exactly what you are about to commit.",
      "",
      "3. **Ctrl-S makes the commit.** You can press it straight from typing --",
      "   no need to leave insert mode first. Or click **✓ Commit** in the bar",
      "   at the top of the box. `q` asks before doing anything, so it is safe",
      "   to press if you change your mind.",
      "",
      "4. `<leader>gP`  -- push it. `<leader>gp` pulls.",
      "",
      "# When you want to choose what goes in",
      "",
      "`<leader>gg` opens the git panel. Its first line lists its own keys:",
      "",
      "  `<Tab>`  open a file up and see the change",
      "  `s`      stage -- mark this for the next commit",
      "  `u`      unstage -- take it back out",
      "  `x`      discard -- throw the change away",
      "  `c`      commit menu (amend, fixup, squash live here)",
      "  `?`      every key the panel has",
      "",
      "# Without opening anything",
      "",
      "  `]h` / `[h`   jump between changes in this file",
      "  `<leader>ghs` stage just the change under the cursor",
      "  `<leader>ghp` preview it first",
      "  `<leader>ghr` throw it away",
      "  `<leader>gd`  review every change side by side",
      "",
      "# Escape hatches",
      "",
      "  `<leader>gz`  lazygit, if you would rather drive a terminal UI",
      "  `<leader>gl`  history, as a graph",
    },
    -- `bo.filetype`, not the `ft` option: snacks sets the scratch buffer's
    -- filetype to "snacks_win" first, and `ft` documents itself as not
    -- overriding an existing one (snacks/win.lua:77). Measured -- the window
    -- opened with ft=snacks_win and no markdown highlighting at all.
    bo = { filetype = "markdown" },
    border = "rounded",
    title = " Git: how do I commit? ",
    title_pos = "center",
    width = 0.6,
    height = 0.8,
    wo = { wrap = false, conceallevel = 2, spell = false },
    keys = { q = "close" },
  })
end

return M
