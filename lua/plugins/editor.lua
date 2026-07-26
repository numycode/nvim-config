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
