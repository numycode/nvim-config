-- The dashboard's "Open folder": the desktop's own directory chooser, then the
-- editor lands in that folder the way JetBrains' File > Open does. Lives here
-- rather than inline in lua/plugins/snacks.lua for two reasons: a dashboard entry
-- can only hold an Ex command string, and the two halves have to be verifiable
-- separately -- nothing can drive a native Qt/GTK dialog headless, while
-- `M.enter()` on its own is a headless probe.
local M = {}

-- The choosers. `desktop` is matched against $XDG_CURRENT_DESKTOP (lowercased; it
-- can be a colon-separated list) and means "prefer me there", and it is checked
-- before anything else -- so kdialog, the Qt/Plasma dialog, wins on KDE and only
-- there. The table's own order is therefore the *fallback* order, for a desktop
-- none of them claims, which is why the generic GTK zenity comes first: on GNOME
-- the reverse ordering silently hands back kdialog. Measured, on the first run of
-- this table. `%s` in an argument is the start directory, so nothing here may
-- contain a literal `%`.
--
-- Not xdg-desktop-portal, even though the -gtk and -kde backends are installed
-- here: there is no `xdg-desktop-portal` binary on PATH to run, so reaching it
-- means a D-Bus call to org.freedesktop.portal.FileChooser plus a Response signal
-- to subscribe to -- a lot of machinery for the same dialog kdialog opens directly.
local DIALOGS = {
  { cmd = "zenity", args = { "--file-selection", "--directory", "--title=Open folder", "--filename=%s/" } },
  { cmd = "yad", args = { "--file", "--directory", "--title=Open folder", "--filename=%s/" } },
  { cmd = "kdialog", desktop = "kde", args = { "--title", "Open folder", "--getexistingdirectory", "%s" } },
}

---@return string[]
local function argv(dialog, start)
  local cmd = { dialog.cmd }

  for _, arg in ipairs(dialog.args) do
    cmd[#cmd + 1] = arg:format(start)
  end

  return cmd
end

--- The chooser to run here, or nil when this machine cannot show one.
---
--- The display check is not redundant with `executable()`. On a bare tty both
--- kdialog and zenity are installed and both exit non-zero with "cannot open
--- display" -- indistinguishable from a cancel, so the feature would silently do
--- nothing instead of falling back to something that works.
---
--- The second pass takes any chooser at all: a Qt dialog on GNOME looks foreign
--- but still returns a directory, which beats no way to open a folder.
local function chooser()
  if (vim.env.DISPLAY or "") == "" and (vim.env.WAYLAND_DISPLAY or "") == "" then
    return nil
  end

  local desktop = (vim.env.XDG_CURRENT_DESKTOP or ""):lower()

  for _, dialog in ipairs(DIALOGS) do
    if dialog.desktop and desktop:find(dialog.desktop, 1, true) and vim.fn.executable(dialog.cmd) == 1 then
      return dialog
    end
  end

  for _, dialog in ipairs(DIALOGS) do
    if vim.fn.executable(dialog.cmd) == 1 then
      return dialog
    end
  end
end

--- Move the whole editor into `dir` and pick up where that folder left off.
---
--- Public on purpose, and not only because the dialog calls it: this half is the
--- entire feature, and it is the half that can be driven headless.
---@param dir string
function M.enter(dir)
  -- normalize() also expands a leading `~`, which is what the typed fallback below
  -- hands over; the trim removes the newline every one of these dialogs prints
  -- after the path.
  dir = vim.fs.normalize(vim.trim(dir))

  if vim.fn.isdirectory(dir) == 0 then
    vim.notify("Not a folder:\n" .. dir, vim.log.levels.WARN, { title = "Open folder" })
    return
  end

  -- `:cd`, not `:tcd` or `:lcd` -- the point of the feature is that the grep, the
  -- file finder, the git bar and the session's own `curdir` all agree on where we
  -- are. `:cd` also clears any window-local directory (:h :cd), which is what makes
  -- that true of every window rather than just this one, and is the reason for the
  -- Ex command over `vim.fn.chdir()`, whose scope depends on whether the current
  -- window happens to have an `lcd`.
  --
  -- fnameescape because a folder picked in a graphical chooser has spaces in it as
  -- a matter of course. pcall because a directory with no `x` permission passes
  -- isdirectory() and fails here with E472, and the dashboard must not be left with
  -- a stack trace on it.
  local ok, err = pcall(vim.cmd, "cd " .. vim.fn.fnameescape(dir))

  if not ok then
    -- pcall hands back the whole nvim_exec2 call stack wrapped around Vim's own
    -- message ('[string "vim/_core/editor"]:355: ... Vim(cd):E472: Command
    -- failed'), which is noise in a notification -- measured on a folder with its
    -- execute bit removed, the case this branch exists for.
    local reason = tostring(err):match("E%d+:.*") or tostring(err)

    vim.notify("Could not open:\n" .. dir .. "\n" .. reason, vim.log.levels.ERROR, { title = "Open folder" })
    return
  end

  -- This require is what *loads* persistence.nvim: it is `event = "BufReadPre"`
  -- (lua/plugins/editor.lua), so on a bare dashboard it is not loaded at all and
  -- `Config.options.dir` -- which current() reads -- is still empty. lazy.nvim's
  -- require hook runs the plugin's `config` synchronously, so setup() has happened
  -- by the time this returns.
  --
  -- It has to come after the cd: current() is built from getcwd() and from
  -- `git branch --show-current` run in the process's cwd (persistence/init.lua:11-21).
  local persistence = require("persistence")
  local session = persistence.current()

  if vim.fn.filereadable(session) == 0 then
    -- The same fallback load() applies internally (persistence/init.lua:81-84): a
    -- session saved on a feature branch carries the branch in its name, so a folder
    -- can have a branch session, a plain one, or neither. Only existence is decided
    -- here -- load() re-resolves the file itself, so the two cannot disagree.
    session = persistence.current({ branch = false })
  end

  if vim.fn.filereadable(session) ~= 0 then
    persistence.load()
    return
  end

  -- No session: leave the sidebar open on the new folder, so the first thing on
  -- screen is the folder that was just chosen. An explorer that is *already* open
  -- needs nothing done to it -- upstream puts a global DirChanged handler on the
  -- picker's list window (picker/source/explorer.lua:83-90) that re-roots and
  -- re-finds it. What must be avoided is opening a second one, hence the same
  -- Snacks.picker.get test the tabline button uses (lua/plugins/ui.lua:287).
  if not Snacks.picker.get({ source = "explorer" })[1] then
    Snacks.explorer()
  end
end

--- The keyboard version, for a machine with no dialog: same continuation, typed.
--- `completion = "dir"` gives Tab completion, in snacks.input and in the builtin
--- prompt alike.
local function prompt(start)
  vim.ui.input({ prompt = "Folder: ", default = start .. "/", completion = "dir" }, function(input)
    if input and vim.trim(input) ~= "" then
      M.enter(input)
    end
  end)
end

-- One dialog at a time. The chooser is spawned rather than waited on, so the editor
-- stays responsive and nothing stops the key being pressed again -- and two dialogs
-- mean two `:cd`s racing each other to different folders.
local pending = false

--- The dashboard's "Open folder". Asks the desktop for a directory, then hands it to
--- M.enter(). Cancelling does nothing at all: an empty answer is the normal way out
--- of a file dialog, not a failure worth announcing.
function M.open()
  local start = vim.uv.os_homedir() or vim.env.HOME or vim.fn.getcwd()
  local dialog = chooser()

  if not dialog then
    vim.notify(
      "No desktop folder chooser here, so type the path instead.\nInstall kdialog or zenity for the graphical one.",
      vim.log.levels.WARN,
      { title = "Open folder" }
    )
    prompt(start)
    return
  end

  if pending then
    return
  end

  pending = true

  vim.system(argv(dialog, start), { text = true }, function(out)
    pending = false

    local chosen = vim.trim(tostring(out.stdout or ""))

    if chosen == "" then
      -- Cancel is tested as "printed nothing", not as an exit code: kdialog and
      -- zenity both exit 1 when cancelled, but a chooser that exits 0 with nothing
      -- selected must not be read as "open /". Anything past 1 is a real failure --
      -- a missing display, a broken Qt theme -- and saying so beats looking like a
      -- key that does nothing.
      if out.code > 1 then
        local reason = vim.trim(tostring(out.stderr or ""))

        vim.notify(
          dialog.cmd .. " failed (" .. out.code .. ")" .. (reason ~= "" and ":\n" .. reason or ""),
          vim.log.levels.ERROR,
          { title = "Open folder" }
        )
      end

      return
    end

    -- vim.system callbacks run in a fast event context, where the cd, the session
    -- source and the picker are all illegal -- the same reason ui.lua schedules its
    -- redraw out of the git callbacks.
    vim.schedule(function() M.enter(chosen) end)
  end)
end

return M
