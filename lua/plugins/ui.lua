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
          "branch",
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
        enable = function(buf, win, _)
          if
            not vim.api.nvim_buf_is_valid(buf)
            or not vim.api.nvim_win_is_valid(win)
            or vim.fn.win_gettype(win) ~= ""
            or vim.wo[win].winbar ~= ""
            or vim.bo[buf].ft == "help"
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
        { "<leader>gh", group = "hunk" },
        { "<leader>m", group = "multicursor" },
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
