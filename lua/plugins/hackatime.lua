-- Time tracking, pointed at a self-hosted Hackatime instance. Only our surfaces are
-- branded: the plugin is still vim-wakatime, the binary is still wakatime-cli, and
-- the commands are still :WakaTime*.
--
-- The API key and server live in ~/.wakatime.cfg, which is hand-maintained. Nothing
-- here writes to it -- note that :WakaTimeStatusBarEnable, :WakaTimeDebugEnable and
-- :WakaTimeApiKey all rewrite that file, so settings go through setup() instead.
return {
  {
    "wakatime/vim-wakatime",
    -- Sourcing this plugin costs ~19ms; nothing needs it during the first frame.
    event = "VeryLazy",
    -- plugin/wakatime.vim calls require("wakatime").setup() with no options the
    -- moment it is sourced, and a second setup() early-returns on state.initialized
    -- having merged only what it can still apply. Claiming g:loaded_wakatime makes
    -- that file finish immediately, so the call below is the only one and its
    -- options are in force during init rather than after it.
    init = function() vim.g.loaded_wakatime = 1 end,
    config = function()
      require("wakatime").setup({
        -- Feeds require("wakatime").statusline(), which lualine renders. Set here
        -- rather than with :WakaTimeStatusBarEnable, which would edit the cfg.
        status_bar_enabled = true,
      })
    end,
  },
}
