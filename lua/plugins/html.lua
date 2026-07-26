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
}
