return {
  -- Problems panel.
  {
    "folke/trouble.nvim",
    cmd = { "Trouble" },
    opts = {
      focus = true,
    },
    keys = {
      { "<leader>xx", "<cmd>Trouble diagnostics toggle<CR>", desc = "Diagnostics (workspace)" },
      {
        "<leader>xX",
        "<cmd>Trouble diagnostics toggle filter.buf=0<CR>",
        desc = "Diagnostics (buffer)",
      },
      {
        "<leader>xs",
        "<cmd>Trouble symbols toggle win.position=right<CR>",
        desc = "Symbols",
      },
      {
        "<leader>xr",
        "<cmd>Trouble lsp toggle win.position=right<CR>",
        desc = "LSP references / definitions",
      },
      { "<leader>xq", "<cmd>Trouble qflist toggle<CR>", desc = "Quickfix list" },
      { "<leader>xL", "<cmd>Trouble loclist toggle<CR>", desc = "Location list" },
    },
  },

  -- TODO / FIXME / HACK tool window.
  {
    "folke/todo-comments.nvim",
    event = { "BufReadPost", "BufNewFile" },
    dependencies = { "nvim-lua/plenary.nvim" },
    opts = {
      signs = true,
    },
    keys = {
      { "<leader>xt", "<cmd>Trouble todo toggle<CR>", desc = "TODOs" },
      {
        "<leader>st",
        function() require("snacks").picker.todo_comments() end,
        desc = "TODOs (picker)",
      },
      {
        "]t",
        function() require("todo-comments").jump_next() end,
        desc = "Next TODO",
      },
      {
        "[t",
        function() require("todo-comments").jump_prev() end,
        desc = "Previous TODO",
      },
    },
  },

  -- Persistent Structure view, kept open alongside the buffer.
  {
    "stevearc/aerial.nvim",
    cmd = { "AerialToggle", "AerialOpen", "AerialNavToggle" },
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
      "nvim-tree/nvim-web-devicons",
    },
    opts = {
      layout = {
        default_direction = "right",
        min_width = 30,
      },
      attach_mode = "global",
      show_guides = true,
      filter_kind = false,
    },
    keys = {
      { "<leader>cO", "<cmd>AerialToggle<CR>", desc = "Outline (structure)" },
    },
  },

  -- AceJump-style motions.
  {
    "folke/flash.nvim",
    event = "VeryLazy",
    opts = {},
    keys = {
      {
        "s",
        mode = { "n", "x", "o" },
        function() require("flash").jump() end,
        desc = "Flash jump",
      },
      {
        -- Deliberately not mapped in visual mode: nvim-surround owns `S` there.
        "S",
        mode = { "n", "o" },
        function() require("flash").treesitter() end,
        desc = "Flash treesitter",
      },
      {
        "<C-s>",
        mode = { "c" },
        function() require("flash").toggle() end,
        desc = "Toggle flash search",
      },
    },
  },

  -- Surround With (JetBrains Ctrl+Alt+T).
  {
    "kylechui/nvim-surround",
    event = "VeryLazy",
    version = "*",
    opts = {},
  },

  -- Multiple cursors (JetBrains Alt+J / Ctrl+Alt+Shift+J).
  {
    "jake-stewart/multicursor.nvim",
    branch = "1.0",
    event = "VeryLazy",
    config = function()
      local mc = require("multicursor-nvim")
      mc.setup()

      local function map(mode, lhs, rhs, desc) vim.keymap.set(mode, lhs, rhs, { silent = true, desc = desc }) end

      -- Add a cursor on the next/previous match of the word under the cursor.
      map({ "n", "x" }, "<leader>ma", function() mc.matchAddCursor(1) end, "Add cursor at next match")
      map({ "n", "x" }, "<leader>mA", function() mc.matchAddCursor(-1) end, "Add cursor at prev match")
      map({ "n", "x" }, "<leader>ms", function() mc.matchSkipCursor(1) end, "Skip next match")
      map({ "n", "x" }, "<leader>mm", function() mc.matchAllAddCursors() end, "Cursor on every match")

      -- Add cursors vertically, like a column selection.
      map({ "n", "x" }, "<C-Down>", function() mc.lineAddCursor(1) end, "Add cursor below")
      map({ "n", "x" }, "<C-Up>", function() mc.lineAddCursor(-1) end, "Add cursor above")

      -- Split a visual selection into one cursor per line.
      map("x", "<leader>ml", mc.splitCursors, "Split selection into cursors")
      map("x", "I", mc.insertVisual, "Insert at start of each line")
      map("x", "A", mc.appendVisual, "Append at end of each line")

      -- <Esc> clears the extra cursors only while they exist, so it keeps its
      -- normal nohlsearch behaviour the rest of the time.
      mc.addKeymapLayer(function(layer)
        layer({ "n", "x" }, "<left>", mc.prevCursor)
        layer({ "n", "x" }, "<right>", mc.nextCursor)
        layer("n", "<esc>", function()
          if not mc.cursorsEnabled() then
            mc.enableCursors()
          else
            mc.clearCursors()
          end
        end)
      end)
    end,
  },

  -- Extract method / extract variable (JetBrains Ctrl+Alt+M / Ctrl+Alt+V).
  {
    "ThePrimeagen/refactoring.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-treesitter/nvim-treesitter",
    },
    opts = {},
    keys = {
      {
        "<leader>rr",
        function() require("refactoring").select_refactor() end,
        mode = { "n", "x" },
        desc = "Refactor…",
      },
      {
        "<leader>rf",
        function() require("refactoring").refactor("Extract Function") end,
        mode = "x",
        desc = "Extract function",
      },
      {
        "<leader>rv",
        function() require("refactoring").refactor("Extract Variable") end,
        mode = "x",
        desc = "Extract variable",
      },
      {
        "<leader>ri",
        function() require("refactoring").refactor("Inline Variable") end,
        mode = { "n", "x" },
        desc = "Inline variable",
      },
    },
  },

  -- Reopen a project where you left it.
  {
    "folke/persistence.nvim",
    event = "BufReadPre",
    opts = {},
    keys = {
      {
        "<leader>Ss",
        function() require("persistence").load() end,
        desc = "Restore session",
      },
      {
        "<leader>Sl",
        function() require("persistence").load({ last = true }) end,
        desc = "Restore last session",
      },
      {
        "<leader>Sd",
        function() require("persistence").stop() end,
        desc = "Do not save session",
      },
    },
  },
}
