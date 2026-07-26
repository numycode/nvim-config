return {
  {
    "saghen/blink.cmp",
    event = { "InsertEnter", "CmdlineEnter" },
    dependencies = {
      {
        "L3MON4D3/LuaSnip",
        dependencies = { "rafamadriz/friendly-snippets" },
        -- blink is pulled in during startup by config.lsp.capabilities(), and
        -- lazy.nvim always loads dependencies with their parent, so LuaSnip
        -- itself cannot be deferred. Scanning the friendly-snippets collection
        -- can be, which is the bulk of the cost.
        config = function()
          vim.schedule(function() require("luasnip.loaders.from_vscode").lazy_load() end)
        end,
      },
    },
    -- Tagged releases ship a prebuilt Rust fuzzy matcher, downloaded on first
    -- run, so no build step and no Rust toolchain are required. If the download
    -- is unavailable on some platform, set `fuzzy.implementation = "lua"` below.
    version = "*",
    ---@module 'blink.cmp'
    ---@type blink.cmp.Config
    opts = {
      -- default preset: <C-y> accept, <C-n>/<C-p> cycle, <C-space> menu/docs,
      -- <C-e> hide, <C-k> signature help.
      keymap = { preset = "default" },
      snippets = { preset = "luasnip" },
      appearance = {
        nerd_font_variant = "mono",
      },
      -- Parameter hints, equivalent to JetBrains Ctrl+P.
      signature = {
        enabled = true,
        window = { border = "rounded" },
      },
      completion = {
        -- JetBrains shows documentation alongside the completion list by default.
        documentation = {
          auto_show = true,
          auto_show_delay_ms = 200,
          window = { border = "rounded" },
        },
        menu = {
          border = "rounded",
          draw = {
            treesitter = { "lsp" },
          },
        },
        ghost_text = { enabled = true },
      },
      sources = {
        default = { "lsp", "path", "snippets", "buffer" },
      },
      -- Finally wires up cmdline completion, which cmp-cmdline was installed
      -- for but never configured.
      cmdline = {
        enabled = true,
        keymap = { preset = "cmdline" },
        completion = {
          menu = { auto_show = true },
          list = { selection = { preselect = false, auto_insert = true } },
        },
      },
      fuzzy = { implementation = "rust" },
    },
    opts_extend = { "sources.default" },
  },

  {
    "windwp/nvim-autopairs",
    event = "InsertEnter",
    opts = {
      check_ts = true,
    },
  },
}
