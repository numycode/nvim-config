return {
  -- The gutter: hunk signs, staging, blame. LazyGit (<leader>gz) and the git
  -- pickers live in lua/plugins/snacks.lua.
  {
    "lewis6991/gitsigns.nvim",
    event = { "BufReadPre", "BufNewFile" },
    opts = {
      signs = {
        add = { text = "▎" },
        change = { text = "▎" },
        delete = { text = "" },
        topdelete = { text = "" },
        changedelete = { text = "▎" },
        untracked = { text = "▎" },
      },
      current_line_blame_opts = {
        delay = 300,
        virt_text_pos = "eol",
      },
      on_attach = function(bufnr)
        local gs = require("gitsigns")

        local function map(mode, lhs, rhs, desc)
          vim.keymap.set(mode, lhs, rhs, {
            buffer = bufnr,
            silent = true,
            desc = desc,
          })
        end

        map("n", "]h", function()
          if vim.wo.diff then
            vim.cmd.normal({ "]c", bang = true })
          else
            gs.nav_hunk("next")
          end
        end, "Next change in this file")

        map("n", "[h", function()
          if vim.wo.diff then
            vim.cmd.normal({ "[c", bang = true })
          else
            gs.nav_hunk("prev")
          end
        end, "Previous change in this file")

        map("n", "<leader>ghs", gs.stage_hunk, "Stage this change")
        map("n", "<leader>ghr", gs.reset_hunk, "Discard this change")
        map(
          "v",
          "<leader>ghs",
          function() gs.stage_hunk({ vim.fn.line("."), vim.fn.line("v") }) end,
          "Stage selected lines"
        )
        map(
          "v",
          "<leader>ghr",
          function() gs.reset_hunk({ vim.fn.line("."), vim.fn.line("v") }) end,
          "Discard selected lines"
        )

        map("n", "<leader>ghS", gs.stage_buffer, "Stage the whole file")
        map("n", "<leader>ghR", gs.reset_buffer, "Discard all changes in this file")
        map("n", "<leader>ghp", gs.preview_hunk_inline, "Preview this change")
        map("n", "<leader>ghd", gs.diffthis, "Compare this file with the last commit")
        map("n", "<leader>ghb", function() gs.blame_line({ full = true }) end, "Who last changed this line")
        map("n", "<leader>ghB", gs.toggle_current_line_blame, "Toggle inline blame for every line")

        map({ "o", "x" }, "ih", gs.select_hunk, "Change (hunk)")
      end,
    },
  },

  -- Full-file diff review and 3-way merge conflict resolution, which is what
  -- lazygit is weakest at.
  {
    "sindrets/diffview.nvim",
    cmd = {
      "DiffviewOpen",
      "DiffviewClose",
      "DiffviewFileHistory",
      "DiffviewToggleFiles",
    },
    opts = {
      enhanced_diff_hl = true,
      view = {
        merge_tool = {
          layout = "diff3_mixed",
          disable_diagnostics = true,
        },
      },
    },
    keys = {
      { "<leader>gd", "<cmd>DiffviewOpen<CR>", desc = "Review all my changes side-by-side" },
      { "<leader>gD", "<cmd>DiffviewClose<CR>", desc = "Close the review view" },
      { "<leader>gf", "<cmd>DiffviewFileHistory %<CR>", desc = "History of this file" },
      { "<leader>gF", "<cmd>DiffviewFileHistory<CR>", desc = "History of this branch" },
    },
  },

  -- The commit tool window. Neogit is a magit port: one status buffer where
  -- staging, committing, branching, rebasing and pushing all happen without
  -- leaving the editor. This is the JetBrains Git panel the config was missing;
  -- lazygit (<leader>gz) stays as the terminal-shaped alternative.
  --
  -- Deliberately thin at the leader level. Everything except open/commit/push/
  -- pull/log is reached from inside the status buffer (`s` stage, `u` unstage,
  -- `d` diffview, `b` branch, `Z` stash), so the git namespace does not grow a
  -- second, worse copy of a UI that already has good keys.
  {
    "NeogitOrg/neogit",
    cmd = "Neogit",
    dependencies = {
      "nvim-lua/plenary.nvim",
      -- Both are optional to Neogit and both are already installed, but they
      -- have to be declared: an unloaded lazy plugin is not on the runtimepath,
      -- so `require("diffview")` from inside Neogit would fail. Declaring them
      -- does not make them eager -- a dependency loads with its parent.
      "sindrets/diffview.nvim",
      "folke/snacks.nvim",
    },
    opts = {
      -- Its own tab page, so the editor's window layout survives being
      -- interrupted and closing it puts everything back exactly as it was.
      kind = "tab",
      -- "kitty" needs the kitty graphics protocol and this is an iTerm2 config
      -- (see the <C-_> terminal map), so unicode box-drawing is the best that
      -- renders here. "ascii" is the fallback if the Nerd Font is missing.
      graph_style = "unicode",
      -- snacks.notifier already reports what Neogit is doing; the spinner
      -- repaints the status buffer on a timer to say the same thing.
      process_spinner = false,
      commit_editor = {
        -- A tab, not a split: with `show_staged_diff` the editor is a message
        -- buffer *plus* a diff buffer, and `staged_diff_split_kind` splits them
        -- inside this window. Making the window itself a split leaves both
        -- panes a few lines tall. A tab is the roomy JetBrains commit dialog:
        -- message on top, exactly what you are about to commit underneath.
        kind = "tab",
        show_staged_diff = true,
        staged_diff_split_kind = "split",
      },
      -- <C-s> as a *second* Submit key, in both modes. Neogit binds a mapping
      -- table's key through util.tbl_wrap (lib/buffer.lua:794), so a list of
      -- keys per action is supported and <c-c><c-c> survives untouched.
      --
      -- <C-s> rather than VSCode's <C-Enter>: iTerm2 without the kitty keyboard
      -- protocol cannot tell <C-CR> from <CR>, and this is an iTerm2 config.
      --
      -- The injected "# Commands:" block will not necessarily mention it --
      -- editor/init.lua:110-113 prints mapping[name][1], and that list's order
      -- is pairs() order over the merged config table. Which is why the winbar
      -- in config/autocmds.lua carries the hint that anyone actually reads.
      mappings = {
        commit_editor = { ["<c-s>"] = "Submit" },
        commit_editor_I = { ["<c-s>"] = "Submit" },
      },
      integrations = {
        -- `d` on a file reuses the diffview configured above, with
        -- enhanced_diff_hl and the diff3_mixed merge layout. <leader>gd/gf/gF
        -- stay the standalone entry points.
        diffview = true,
        snacks = true,
        telescope = false,
        fzf_lua = false,
        mini_pick = false,
      },
    },
    -- Neogit's popups are menus of variants -- the commit popup alone offers
    -- twelve (commit, amend, fixup, squash, absorb...) and you press a second
    -- key to do the ordinary thing. That is the classic magit stumble, so where
    -- possible these keys run the one obvious action directly through
    -- `neogit.action(popup, action)`, the documented API that returns the
    -- function the popup would have called.
    --
    -- Push and pull do. **Commit deliberately does not**: measured here,
    -- `neogit.action("commit", "commit")()` blocks the event loop and opens no
    -- editor -- the stub popup that `action()` synthesises is not enough for
    -- `do_commit`. `:Neogit commit` then `c` works in the identical harness, so
    -- the popup is not a preference, it is the only thing that works. It is also
    -- a labelled menu with Commit first, which is a fair place to land.
    --
    -- Either way the popups stay reachable: `c`, `p`, `P`, `b`, `Z` inside the
    -- status buffer are where you go to amend or force-push. Leader = the common
    -- thing; the panel = full power.
    keys = {
      { "<leader>gg", "<cmd>Neogit<CR>", desc = "Git panel: stage, commit, push" },
      {
        "<leader>gc",
        function() require("config.git").commit() end,
        desc = "Commit -- type a message, then Ctrl-S",
      },
      {
        "<leader>g?",
        function() require("config.git").cheatsheet() end,
        desc = "How do I commit? (plain-English walkthrough)",
      },
      -- p pulls and P pushes, matching the status buffer's own `p`/`P` (and
      -- magit's, and therefore Neogit's documentation). Binding <leader>gp to
      -- push would read better in isolation but would mean the same letter did
      -- opposite things on the two surfaces you use most -- one rule is worth
      -- more than one convenient key.
      {
        "<leader>gp",
        function() require("neogit").action("pull", "from_pushremote")() end,
        desc = "Pull: download commits from remote",
      },
      {
        -- "pushremote" rather than "upstream": pushing to `@{upstream}` fails on
        -- a branch that has never been pushed, which is exactly when a beginner
        -- reaches for this. The pushremote variant sets the upstream for you.
        "<leader>gP",
        function() require("neogit").action("push", "to_pushremote")() end,
        desc = "Push: upload commits to remote",
      },
      { "<leader>gl", "<cmd>Neogit log<CR>", desc = "History: commit graph" },
    },
  },

  -- Inline conflict resolution: the markers are highlighted as current/incoming
  -- blocks so a two-sided conflict never needs the 3-way diffview at <leader>gd.
  --
  -- `default_mappings = false` because the defaults (co/ct/cb/c0, ]x/[x) carry no
  -- `desc`, and which-key is how anything here is found. co/ct/cb would also
  -- shadow the `c` operator's prefix in a conflicted buffer, adding a timeoutlen
  -- stall to `cw`. The maps below are the same actions with descriptions.
  --
  -- Everything here targets `<Plug>(git-conflict-*)` rather than the plugin's own
  -- `:GitConflictChooseOurs` / `:GitConflict{Next,Prev}Conflict` commands, which
  -- are **broken upstream**: `set_commands()` builds them with a `<Plug>` *string*
  -- as the body (git-conflict.lua:503-511), and Vim runs a string body as an Ex
  -- command line, so every one of them fails with
  --   E492: Not an editor command: <80><fd>S(git-conflict-ours)
  -- Measured on this machine, not inferred. `:GitConflictListQf` and
  -- `:GitConflictRefresh` take function bodies and do work, hence `gxq` below.
  {
    "akinsho/git-conflict.nvim",
    -- Detection reads the buffer's contents, so it must be loaded before the
    -- file is; a `keys` loader would mean no highlights until you pressed ]x.
    -- Same loader gitsigns and todo-comments already use, and a bare `nvim`
    -- fires neither event.
    event = { "BufReadPost", "BufNewFile" },
    opts = {
      default_mappings = false,
      default_commands = true,
      -- MUST stay false on Neovim 0.12: the plugin implements this by calling
      -- `vim.diagnostic.disable()` (git-conflict.lua:655), which 0.12 removed --
      -- it is nil here, so enabling this throws inside the plugin's own
      -- GitConflictDetected handler. The behaviour is worth having, so the
      -- autocmd below does it with the supported API instead.
      disable_diagnostics = false,
      list_opener = "copen",
      highlights = {
        current = "DiffText",
        incoming = "DiffAdd",
      },
    },
    keys = {
      { "]x", "<Plug>(git-conflict-next-conflict)", desc = "Next conflict" },
      { "[x", "<Plug>(git-conflict-prev-conflict)", desc = "Previous conflict" },
      { "<leader>gxq", "<cmd>GitConflictListQf<CR>", desc = "List all conflicts" },
    },
    config = function(_, opts)
      require("git-conflict").setup(opts)

      local group = vim.api.nvim_create_augroup("git-conflict-maps", { clear = true })

      -- The plugin fires these with no payload -- `nvim_exec_autocmds("User",
      -- { pattern = ... })` and nothing else (git-conflict.lua:408) -- so the
      -- buffer has to come from the current window, which is what the plugin's
      -- own handler does too.
      vim.api.nvim_create_autocmd("User", {
        group = group,
        pattern = "GitConflictDetected",
        callback = function()
          local buf = vim.api.nvim_get_current_buf()

          -- A file full of <<<<<<< markers does not parse; every LSP and linter
          -- attached to it reports nonsense until the conflict is resolved.
          -- Shares state with Snacks.toggle.diagnostics() on <leader>ud, which
          -- will therefore read "off" inside a conflicted buffer.
          vim.diagnostic.enable(false, { bufnr = buf })

          -- Only once a conflict is present, and only in that buffer: these four
          -- would otherwise clutter which-key in every file. The mirror event
          -- takes them away, so a resolved file stops advertising them.
          local function map(lhs, plug, desc)
            vim.keymap.set("n", lhs, plug, { buffer = buf, silent = true, remap = true, desc = desc })
          end

          map("<leader>gxo", "<Plug>(git-conflict-ours)", "Keep MY version (current)")
          map("<leader>gxt", "<Plug>(git-conflict-theirs)", "Keep THEIR version (incoming)")
          map("<leader>gxb", "<Plug>(git-conflict-both)", "Keep both versions")
          map("<leader>gxn", "<Plug>(git-conflict-none)", "Keep neither -- delete both")
        end,
      })

      vim.api.nvim_create_autocmd("User", {
        group = group,
        pattern = "GitConflictResolved",
        callback = function()
          local buf = vim.api.nvim_get_current_buf()

          vim.diagnostic.enable(true, { bufnr = buf })

          for _, lhs in ipairs({ "<leader>gxo", "<leader>gxt", "<leader>gxb", "<leader>gxn" }) do
            pcall(vim.keymap.del, "n", lhs, { buffer = buf })
          end
        end,
      })
    end,
  },
}
