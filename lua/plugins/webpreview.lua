-- Live preview of HTML, Markdown, AsciiDoc and SVG in the system browser, with
-- the page reloading as the file changes. The JetBrains "run in browser" arrow,
-- which this config otherwise had no equivalent of.
--
-- The backend is pure Lua on vim.uv -- a TCP listener and a hand-written
-- websocket, no node and no python. That matters here: options.lua disables the
-- node and python3 provider hosts on purpose, and a `npx live-server` would drag
-- a download into the click path.
--
-- The statusline button that drives this lives in lua/plugins/ui.lua; it reads
-- `require("livepreview").is_running()` for its state.
return {
  {
    "brianhuster/live-preview.nvim",
    -- Loaded by the command, so a bare `nvim` pays nothing for it. The button in
    -- the statusline goes through `:LivePreview` for exactly this reason.
    cmd = "LivePreview",
    keys = {
      -- Start and stop go through config.preview rather than straight at the
      -- commands, for the `silent` and for the Linux fswatch recovery -- see the
      -- comments there. `pick` has neither problem and stays a plain command.
      { "<leader>pp", function() require("config.preview").toggle() end, desc = "Toggle live preview" },
      { "<leader>po", function() require("config.preview").start() end, desc = "Open live preview in browser" },
      { "<leader>pf", "<cmd>LivePreview pick<CR>", desc = "Pick a file to preview" },
      { "<leader>px", function() require("config.preview").stop() end, desc = "Stop live preview server" },
    },
    config = function()
      -- `require("livepreview").setup()` is marked deprecated upstream; this is
      -- the current entry point.
      require("livepreview.config").set({
        port = require("config.preview").port,
        -- "default" means vim.ui.open, i.e. whatever the OS opens an http:// URL
        -- with. Anything else is a shell command the plugin appends the URL to,
        -- which would need a per-OS branch to stay portable.
        browser = "default",
        -- Webroot is the cwd rather than the file's own directory, so `../` and
        -- `/assets/...` links resolve the way they will once the page is served
        -- for real.
        dynamic_root = false,
        -- Left empty on purpose, which means "auto-detect". Naming the picker is
        -- the documented way and it is broken: `LivePreview.pick` builds its
        -- lookup as `picker[key]` over the `pickers` enum, and while that enum
        -- advertises "snacks.picker" the picker module has no `snacks` function
        -- to resolve to. The value validates, then fails at use with "config
        -- option 'picker' invalid" -- verified, that notification is all
        -- <leader>pf produced. The auto-detect branch handles snacks properly,
        -- through `vimui` + `snacks.picker.select`.
        picker = "",
      })
    end,
  },
}
