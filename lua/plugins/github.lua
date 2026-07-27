-- GitHub code review inside the editor: PR and issue lists, threaded comments,
-- and a review mode that diffs the PR and takes line comments. This is the half
-- of the JetBrains git experience Neogit does not cover.
--
-- Everything here goes through the `gh` CLI, which install.sh already installs
-- as an optional tool. It must be authenticated (`gh auth login`) first --
-- octo reports that failure, it cannot fix it.
return {
  {
    "pwntester/octo.nvim",
    cmd = "Octo",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "folke/snacks.nvim",
      "nvim-tree/nvim-web-devicons",
    },
    opts = {
      -- The same picker as everything else, so the PR list behaves like
      -- <leader>ff instead of introducing a second fuzzy-finder's keybindings.
      picker = "snacks",
      enable_builtin = true,
      -- `true` checks the PR branch out into the working tree, which is shared
      -- with Neogit, gitsigns and the running language servers. Reviewing should
      -- not move HEAD; the buffers come from the API instead.
      use_local_fs = false,
      default_merge_method = "squash",
      -- A token from `gh auth login` has no read:project scope, and octo warns
      -- about the missing scope on every start otherwise.
      suppress_missing_scope = { projects_v2 = true },
      ui = {
        -- snacks owns the status column globally (folds plus git signs); octo's
        -- own would replace it inside review buffers and lose the fold column.
        use_statuscolumn = false,
      },
    },
    keys = {
      { "<leader>gop", "<cmd>Octo pr list<CR>", desc = "Pull requests" },
      { "<leader>goP", "<cmd>Octo pr search<CR>", desc = "Search pull requests" },
      { "<leader>goc", "<cmd>Octo pr create<CR>", desc = "Create pull request" },
      { "<leader>goi", "<cmd>Octo issue list<CR>", desc = "Issues" },
      { "<leader>goI", "<cmd>Octo issue search<CR>", desc = "Search issues" },
      { "<leader>gor", "<cmd>Octo review start<CR>", desc = "Start review" },
      { "<leader>goR", "<cmd>Octo review resume<CR>", desc = "Resume review" },
      { "<leader>gon", "<cmd>Octo notification list<CR>", desc = "Notifications" },
    },
  },
}
