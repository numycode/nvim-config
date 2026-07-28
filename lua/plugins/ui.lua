-- Backs the statusline's live-preview button. Kept in its own module because the
-- <leader>p keymaps in plugins/webpreview.lua drive the same toggle. Required in
-- lualine's `config` rather than here, for the reason gitbar_watch() is: this file
-- is read during startup, and a bare `nvim` should pay for neither.
local preview

-- Custom-area highlights take literal colours rather than a highlight link, so pull
-- one from the active colorscheme instead of hardcoding a tokyonight blue.
local function hl_fg(group)
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = group, link = false })

  return ok and hl.fg and string.format("#%06x", hl.fg) or nil
end

-- Width of the explorer sidebar, or nil when it is closed.
local function sidebar_width()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)

    if
      vim.bo[buf].filetype == "snacks_layout_box"
      and vim.api.nvim_win_get_config(win).relative == ""
      and vim.api.nvim_win_get_position(win)[2] == 0
    then
      return vim.api.nvim_win_get_width(win)
    end
  end
end

-- Width a tabline fragment occupies once its `%` escapes are resolved. This is how
-- bufferline sizes custom areas (bufferline/custom_area.lua), so the two agree.
local function tabline_width(text) return vim.api.nvim_eval_statusline(text, { use_tabline = true }).width end

-- State behind the statusline's git widgets: the Neogit button and the JetBrains
-- ↑2 ↓1 divergence counter.
--
-- lualine renders on every redraw, many times a second while scrolling, so the
-- component functions must do no work at all: they read these two cached fields
-- and nothing else. A synchronous `vim.fn.system("git rev-list ...")` in that
-- position costs ~11ms of blocked UI per keystroke, measured -- against 7.3us to
-- render the whole bar 1000 times from cache.
local gitbar = { text = "", ahead = 0, behind = 0, in_repo = false, pending = false, checked = 0 }

local GITBAR_THROTTLE_MS = 5000

local function gitbar_refresh(force)
  local now = vim.uv.now()

  if gitbar.pending or (not force and now - gitbar.checked < GITBAR_THROTTLE_MS) then
    return
  end

  gitbar.pending, gitbar.checked = true, now

  local cwd = vim.uv.cwd()

  local function publish(field, value)
    -- These callbacks run in a fast event context: assigning to a Lua table is
    -- legal, calling into the API is not, so the redraw is scheduled.
    if gitbar[field] ~= value then
      gitbar[field] = value
      vim.schedule(function() vim.cmd.redrawstatus() end)
    end
  end

  -- Gates the button. `rev-list` below cannot stand in for this: it also fails
  -- inside a perfectly good repo whose branch has no upstream, so a repo you
  -- have not pushed yet would lose its button.
  vim.system(
    { "git", "rev-parse", "--is-inside-work-tree" },
    { cwd = cwd, text = true },
    function(out) publish("in_repo", out.code == 0 and vim.trim(tostring(out.stdout or "")) == "true") end
  )

  -- Left of the `...` is upstream-only (behind), right is HEAD-only (ahead).
  -- Exits non-zero outside a repo and on a branch with no upstream; both mean
  -- "nothing to show", which is what an empty string renders as.
  vim.system(
    { "git", "rev-list", "--left-right", "--count", "@{upstream}...HEAD" },
    { cwd = cwd, text = true },
    function(out)
      local behind, ahead = tostring(out.stdout or ""):match("(%d+)%s+(%d+)")
      local parts = {}

      if out.code ~= 0 or not ahead then
        behind, ahead = "0", "0"
      end

      if ahead ~= "0" then
        parts[#parts + 1] = "↑" .. ahead
      end
      if behind ~= "0" then
        parts[#parts + 1] = "↓" .. behind
      end

      gitbar.pending = false
      -- Kept as numbers too: the click handler needs to know which way the
      -- branch has moved, not just how it reads.
      gitbar.ahead, gitbar.behind = tonumber(ahead), tonumber(behind)
      publish("text", table.concat(parts, " "))
    end
  )
end

-- No polling timer: nothing moves this state without one of these firing, and a
-- timer would keep waking a backgrounded editor to shell out to git.
local function gitbar_watch()
  local group = vim.api.nvim_create_augroup("lualine-gitbar", { clear = true })

  vim.api.nvim_create_autocmd({ "FocusGained", "BufWritePost" }, {
    group = group,
    callback = function() gitbar_refresh(false) end,
  })

  -- Forced: a new cwd is a different repository (or none), so the button has to
  -- appear or disappear now rather than up to a throttle window later.
  vim.api.nvim_create_autocmd("DirChanged", {
    group = group,
    callback = function() gitbar_refresh(true) end,
  })

  -- A glob rather than the individual names: Neogit emits a family of these
  -- (NeogitPushComplete, NeogitCommitComplete, NeogitBranchCheckout, ...) and
  -- every one of them can move the counts.
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "Neogit*",
    callback = function() gitbar_refresh(true) end,
  })

  gitbar_refresh(true)
end

return {
  {
    "nvim-tree/nvim-web-devicons",
    lazy = true,
  },

  -- Statusline. Also restores the mode indicator hidden by `showmode = false`.
  {
    "nvim-lualine/lualine.nvim",
    event = "VeryLazy",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = {
      options = {
        theme = "auto",
        globalstatus = true,
        component_separators = { left = "", right = "" },
        section_separators = { left = "", right = "" },
        disabled_filetypes = {
          statusline = { "snacks_dashboard" },
        },
      },
      sections = {
        lualine_a = { "mode" },
        lualine_b = {
          -- Opens the Neogit status buffer -- the same thing <leader>gg does, as
          -- a mouse target, so the git UI is reachable without knowing the
          -- keymap. The statusline counterpart to the tabline's 󰉋 Files button,
          -- and nf-md-git to that button's nf-md-folder: both live in the
          -- U+F0000 material-design block this config draws its icons from.
          --
          -- Hidden outside a git repo, where clicking it could only ever fail.
          -- `cond` is a plain boolean read of the cache; see `gitbar`.
          {
            function() return "󰊢" end,
            cond = function() return gitbar.in_repo end,
            on_click = function() vim.cmd("Neogit") end,
          },
          {
            "branch",
            -- Clickable, like the branch widget in the JetBrains status bar.
            -- lualine wraps the component in a `%<n>@...@` click label, which
            -- only resolves because `mouse = "a"` is set in options.lua.
            on_click = function() Snacks.picker.git_branches() end,
          },
          -- Divergence from upstream. Both `cond` and the body are pure reads of
          -- the cache above; the git call happens on the autocmds in
          -- gitbar_watch(), never here. See the comment on `gitbar`.
          --
          -- Clicking does what the arrow is telling you: ↑ means commits are
          -- sitting here unsent, ↓ means commits are waiting to come down. Both
          -- at once is a genuine fork in the road -- pushing would be rejected
          -- and pulling may conflict -- so that one opens the panel and lets you
          -- look before acting.
          {
            function() return gitbar.text end,
            cond = function() return gitbar.text ~= "" end,
            on_click = function()
              local neogit = require("neogit")

              if gitbar.ahead > 0 and gitbar.behind > 0 then
                vim.cmd("Neogit")
              elseif gitbar.ahead > 0 then
                neogit.action("push", "to_pushremote")()
              else
                neogit.action("pull", "from_pushremote")()
              end
            end,
          },
          {
            "diff",
            symbols = { added = " ", modified = " ", removed = " " },
          },
        },
        lualine_c = {
          { "filename", path = 1, symbols = { modified = " ", readonly = " " } },
          {
            "diagnostics",
            symbols = { error = " ", warn = " ", info = " ", hint = " " },
          },
        },
        lualine_x = {
          -- Run-in-browser button, on the buffers the preview server can serve.
          -- 󰖟 starts it, 󰓛 stops it; both glyphs come from the same U+F0000
          -- material-design block as the 󰊢 and 󰉋 buttons. The port is shown while
          -- it is up so the URL is guessable without opening the browser again.
          --
          -- `cond` and the body are cheap reads -- see the comments in
          -- config.preview on why neither may require("livepreview") itself.
          {
            function() return preview.running() and ("󰓛 Live :" .. preview.port) or "󰖟 Live" end,
            cond = function() return preview.previewable() end,
            color = function() return preview.running() and "DiagnosticOk" or nil end,
            on_click = function() preview.toggle() end,
          },
          -- Today's Hackatime total, refreshed from wakatime-cli at most once a
          -- minute. The __wakatime_statusline tag is what the plugin looks for
          -- before injecting its own copy of this component -- finding ours, it
          -- leaves the section alone instead of calling lualine.setup() again at
          -- runtime. `cond` reads package.loaded rather than requiring the module,
          -- so the statusline never drags it in ahead of VeryLazy. A failed refresh
          -- writes only to stderr, so the component simply empties.
          {
            function() return require("wakatime").statusline() end,
            cond = function() return package.loaded.wakatime ~= nil end,
            icon = "󱑆",
            __wakatime_statusline = true,
          },
          -- Active LSP clients for the current buffer.
          {
            function()
              local clients = vim.lsp.get_clients({ bufnr = 0 })
              if #clients == 0 then
                return ""
              end

              local names = vim.tbl_map(function(client) return client.name end, clients)

              table.sort(names)
              return " " .. table.concat(names, ", ")
            end,
            cond = function() return vim.bo.buftype == "" end,
          },
          "filetype",
        },
        lualine_y = { "progress" },
        lualine_z = { "location" },
      },
      extensions = { "lazy", "man", "quickfix" },
    },
    config = function(_, opts)
      -- Byte-for-byte what lazy's implicit config does, so the vim-wakatime
      -- component interplay is unaffected -- the watchers are the only addition,
      -- and they are registered here rather than in `init` so a bare `nvim`
      -- pays nothing for them: lualine is VeryLazy, and so is this.
      preview = require("config.preview")

      require("lualine").setup(opts)
      gitbar_watch()
    end,
  },

  -- Editor tabs across the top, with a JetBrains-style project button at the left.
  {
    "akinsho/bufferline.nvim",
    event = "VeryLazy",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    init = function()
      -- Tabline click labels can only reach global functions (`:h statusline`), which
      -- is why this hangs off `_G` rather than living in the spec. Neovim calls it as
      -- (minwid, clicks, button, modifiers); none of that matters here.
      _G.NvimTabline = {
        toggle_explorer = function()
          -- `Snacks.picker.get` filters out closed pickers, so a hit means it is open.
          local explorer = Snacks.picker.get({ source = "explorer" })[1]

          if explorer then
            explorer:close()
          else
            Snacks.explorer()
          end
        end,
      }

      -- Tabs would otherwise be drawn over the dashboard splash. lualine excludes it
      -- via `disabled_filetypes`; bufferline has no equivalent, and its own
      -- `toggle_bufferline` re-pins `showtabline` on every redraw, overriding anything
      -- set here. Hence `auto_toggle_bufferline = false` below: the option is ours.
      local group = vim.api.nvim_create_augroup("bufferline-dashboard", { clear = true })

      vim.api.nvim_create_autocmd("FileType", {
        group = group,
        pattern = "snacks_dashboard",
        callback = function() vim.o.showtabline = 0 end,
      })
      vim.api.nvim_create_autocmd("BufEnter", {
        group = group,
        callback = function()
          if vim.bo.filetype ~= "snacks_dashboard" then
            vim.o.showtabline = 2
          end
        end,
      })
    end,
    opts = {
      options = {
        mode = "buffers",
        diagnostics = "nvim_lsp",
        diagnostics_indicator = function(_, _, diagnostics)
          local icons = { error = " ", warning = " " }
          local result = ""

          for level, count in pairs(diagnostics) do
            local icon = icons[level]
            if icon then
              result = result .. icon .. count
            end
          end

          return result
        end,
        separator_style = "slant",
        show_buffer_close_icons = true,
        show_close_icon = false,
        always_show_bufferline = true,
        auto_toggle_bufferline = false,
        -- The project button, JetBrains style: pinned top-left, toggles the sidebar.
        --
        -- This deliberately replaces bufferline's `offsets` rather than using it.
        -- A custom area is concatenated into the tabline verbatim, so a statusline
        -- click label survives, whereas an offset sizes its text with `nvim_strwidth`
        -- and would count the escapes as visible characters. But offsets also render
        -- *before* custom areas, so keeping one would shove the button 41 columns
        -- right the moment the sidebar opened -- a toggle that runs away from the
        -- pointer. So the area does the offset's job too: pad the tabs clear of the
        -- sidebar and draw the separator that lines up with the window split.
        custom_areas = {
          left = function()
            local label = "  󰉋 Files "
            local areas = {
              {
                text = "%@v:lua.NvimTabline.toggle_explorer@" .. label .. "%X",
                fg = hl_fg("Directory"),
              },
            }
            local width = sidebar_width()

            if width then
              local pad = math.max(width - tabline_width(label), 0)

              -- `WinSeparator` rather than `BufferLineOffsetSeparator`: this character
              -- continues the window split at that column, and the core group is
              -- always defined, whereas bufferline's only exists once it has rendered.
              areas[#areas + 1] = {
                text = string.rep(" ", pad) .. "│",
                fg = hl_fg("WinSeparator"),
              }
            end

            return areas
          end,
        },
      },
    },
    keys = {
      { "<S-h>", "<cmd>BufferLineCyclePrev<CR>", desc = "Previous buffer" },
      { "<S-l>", "<cmd>BufferLineCycleNext<CR>", desc = "Next buffer" },
      { "<leader>bp", "<cmd>BufferLineTogglePin<CR>", desc = "Toggle pin" },
      { "<leader>br", "<cmd>BufferLineCloseRight<CR>", desc = "Close buffers to the right" },
      { "<leader>bl", "<cmd>BufferLineCloseLeft<CR>", desc = "Close buffers to the left" },
    },
  },

  -- Breadcrumbs in the winbar: path > Class > method, clickable and navigable.
  {
    "Bekaboo/dropbar.nvim",
    event = "VeryLazy",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = {
      bar = {
        -- Keep the winbar out of special buffers.
        --
        -- `gitcommit` is excluded by name rather than left to the
        -- `winbar ~= ""` test above: dropbar attaches on BufEnter and FileType
        -- as well as BufWinEnter, and measured on this config it *did* claim
        -- neogit's commit editor, rendering "󰉋 .git  COMMIT_EDITMSG". The
        -- Commit button that lua/config/autocmds.lua puts there is worth more
        -- than a breadcrumb for a path with no structure to break down.
        enable = function(buf, win, _)
          if
            not vim.api.nvim_buf_is_valid(buf)
            or not vim.api.nvim_win_is_valid(win)
            or vim.fn.win_gettype(win) ~= ""
            or vim.wo[win].winbar ~= ""
            or vim.bo[buf].ft == "help"
            or vim.bo[buf].ft == "gitcommit"
          then
            return false
          end

          return vim.bo[buf].buftype == "" and vim.api.nvim_buf_get_name(buf) ~= ""
        end,
      },
    },
    keys = {
      {
        "<leader>cp",
        function() require("dropbar.api").pick() end,
        desc = "Pick breadcrumb",
      },
    },
  },

  -- Sticky scroll: pin the enclosing function/class signature to the top.
  {
    "nvim-treesitter/nvim-treesitter-context",
    event = { "BufReadPost", "BufNewFile" },
    opts = {
      max_lines = 3,
      multiline_threshold = 1,
      trim_scope = "outer",
    },
    keys = {
      {
        "<leader>uc",
        function() require("treesitter-context").toggle() end,
        desc = "Toggle sticky context",
      },
    },
  },

  -- Keymap discovery. This is what replaces JetBrains muscle memory.
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {
      preset = "modern",
      delay = function(ctx) return ctx.plugin and 0 or 300 end,
      spec = {
        { "<leader>b", group = "buffer" },
        { "<leader>c", group = "code" },
        { "<leader>f", group = "find" },
        { "<leader>g", group = "git" },
        { "<leader>gh", group = "changes in this file" },
        { "<leader>go", group = "github" },
        { "<leader>gx", group = "conflict" },
        { "<leader>m", group = "multicursor" },
        { "<leader>p", group = "preview" },
        { "<leader>r", group = "refactor" },
        { "<leader>s", group = "search" },
        { "<leader>S", group = "session" },
        { "<leader>t", group = "terminal" },
        { "<leader>u", group = "ui toggles" },
        { "<leader>x", group = "diagnostics" },
        { "[", group = "prev" },
        { "]", group = "next" },
        { "g", group = "goto" },
      },
    },
    keys = {
      {
        "<leader>?",
        function() require("which-key").show({ global = false }) end,
        desc = "Buffer keymaps",
      },
    },
  },
}
