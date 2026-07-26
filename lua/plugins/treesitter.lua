local ts = require("config.parsers")
local parsers = ts.parsers
local filetypes = ts.filetypes

-- Structural motions and text objects, the rough equivalent of JetBrains'
-- Ctrl+W expand-selection and Alt+Up/Down structural navigation.
local function textobjects()
  local select = require("nvim-treesitter-textobjects.select")
  local move = require("nvim-treesitter-textobjects.move")
  local swap = require("nvim-treesitter-textobjects.swap")

  local function map(mode, lhs, rhs, desc) vim.keymap.set(mode, lhs, rhs, { silent = true, desc = desc }) end

  local selections = {
    { "af", "@function.outer", "a function" },
    { "if", "@function.inner", "inner function" },
    { "ac", "@class.outer", "a class" },
    { "ic", "@class.inner", "inner class" },
    { "aa", "@parameter.outer", "a parameter" },
    { "ia", "@parameter.inner", "inner parameter" },
    { "ai", "@conditional.outer", "a conditional" },
    { "ii", "@conditional.inner", "inner conditional" },
    { "al", "@loop.outer", "a loop" },
    { "il", "@loop.inner", "inner loop" },
  }

  for _, entry in ipairs(selections) do
    local lhs, query, desc = entry[1], entry[2], entry[3]
    map({ "x", "o" }, lhs, function() select.select_textobject(query, "textobjects") end, desc)
  end

  local movements = {
    { "]f", "goto_next_start", "@function.outer", "Next function start" },
    { "[f", "goto_previous_start", "@function.outer", "Previous function start" },
    { "]F", "goto_next_end", "@function.outer", "Next function end" },
    { "[F", "goto_previous_end", "@function.outer", "Previous function end" },
    { "]c", "goto_next_start", "@class.outer", "Next class start" },
    { "[c", "goto_previous_start", "@class.outer", "Previous class start" },
    { "]a", "goto_next_start", "@parameter.inner", "Next parameter" },
    { "[a", "goto_previous_start", "@parameter.inner", "Previous parameter" },
  }

  for _, entry in ipairs(movements) do
    local lhs, fn, query, desc = entry[1], entry[2], entry[3], entry[4]
    map({ "n", "x", "o" }, lhs, function() move[fn](query, "textobjects") end, desc)
  end

  map("n", "<leader>cx", function() swap.swap_next("@parameter.inner") end, "Swap parameter next")

  map("n", "<leader>cX", function() swap.swap_previous("@parameter.inner") end, "Swap parameter previous")
end

return {
  {
    "windwp/nvim-ts-autotag",
    -- Limited to filetypes that actually have a parser installed; the previous
    -- list included TS/Svelte/Vue, for which autotag silently did nothing.
    ft = {
      "html",
      "javascript",
      "javascriptreact",
      "markdown",
      "xml",
    },
    opts = {},
  },
  {
    "nvim-treesitter/nvim-treesitter",
    lazy = false,
    dependencies = {
      {
        "nvim-treesitter/nvim-treesitter-textobjects",
        branch = "main",
        init = function()
          -- Built-in ftplugin maps would otherwise shadow the motions below.
          vim.g.no_plugin_maps = true
        end,
      },
    },
    opts = {
      filetypes = filetypes,
    },
    config = function(_, opts)
      local nvim_treesitter = require("nvim-treesitter")
      nvim_treesitter.setup()

      -- Fetch any parser that is missing. Asynchronous so startup is not
      -- blocked; install.sh calls the same function synchronously during setup.
      local _, _, ts_err = ts.ensure()
      if ts_err then
        vim.notify(ts_err, vim.log.levels.WARN)
      end

      require("nvim-treesitter-textobjects").setup({
        select = {
          lookahead = true,
          selection_modes = {
            ["@function.outer"] = "V",
            ["@class.outer"] = "V",
            ["@parameter.outer"] = "v",
          },
        },
        move = {
          set_jumps = true,
        },
      })

      textobjects()

      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("treesitter_start", { clear = true }),
        pattern = opts.filetypes,
        callback = function() pcall(vim.treesitter.start) end,
      })

      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("treesitter_indent", { clear = true }),
        pattern = opts.filetypes,
        callback = function() vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()" end,
      })
    end,
  },
}
