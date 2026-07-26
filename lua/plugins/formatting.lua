return {
  {
    "stevearc/conform.nvim",
    event = { "BufWritePre" },
    cmd = { "ConformInfo" },
    opts = {
      format_on_save = function(bufnr)
        -- Honour the FormatDisable/FormatEnable commands and <leader>uF.
        if vim.g.disable_autoformat or vim.b[bufnr].disable_autoformat then
          return nil
        end

        return { timeout_ms = 1000, lsp_format = "fallback" }
      end,
      formatters_by_ft = {
        css = { "prettierd" },
        html = { "prettierd" },
        javascript = { "prettierd" },
        javascriptreact = { "prettierd" },
        json = { "prettierd" },
        jsonc = { "prettierd" },
        lua = { "stylua" },
        markdown = { "prettierd" },
        python = { "ruff_format" },
        scss = { "prettierd" },
        sh = { "shfmt" },
        toml = { "taplo" },
        yaml = { "prettierd" },
        ["_"] = { "trim_whitespace" },
      },
    },
    config = function(_, opts)
      require("conform").setup(opts)

      vim.keymap.set(
        { "n", "v" },
        "<leader>cf",
        function() require("conform").format({ async = true, lsp_format = "fallback" }) end,
        { desc = "Format buffer", silent = true }
      )

      vim.api.nvim_create_user_command("FormatDisable", function(args)
        if args.bang then
          vim.b.disable_autoformat = true
        else
          vim.g.disable_autoformat = true
        end
      end, {
        desc = "Disable format on save (! for current buffer only)",
        bang = true,
      })

      vim.api.nvim_create_user_command("FormatEnable", function()
        vim.b.disable_autoformat = false
        vim.g.disable_autoformat = false
      end, {
        desc = "Re-enable format on save",
      })

      vim.keymap.set("n", "<leader>uF", function()
        vim.g.disable_autoformat = not vim.g.disable_autoformat
        vim.notify("Format on save " .. (vim.g.disable_autoformat and "disabled" or "enabled"), vim.log.levels.INFO)
      end, { desc = "Toggle format on save", silent = true })
    end,
  },
}
