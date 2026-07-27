local augroup = vim.api.nvim_create_augroup("user_config", { clear = true })

vim.api.nvim_create_autocmd("TextYankPost", {
  group = augroup,
  desc = "Highlight text after yanking",
  callback = function()
    -- vim.highlight.on_yank is deprecated since 0.11.
    (vim.hl or vim.highlight).on_yank()
  end,
})

vim.api.nvim_create_autocmd("BufReadPost", {
  group = augroup,
  desc = "Restore cursor position when reopening a file",
  callback = function(event)
    local mark = vim.api.nvim_buf_get_mark(event.buf, '"')
    local line_count = vim.api.nvim_buf_line_count(event.buf)

    if mark[1] > 0 and mark[1] <= line_count then
      pcall(vim.api.nvim_win_set_cursor, 0, mark)
    end
  end,
})

vim.api.nvim_create_autocmd("FileType", {
  group = augroup,
  desc = "Close helper windows with q",
  pattern = {
    "checkhealth",
    "gitsigns-blame",
    "help",
    "lspinfo",
    "man",
    "notify",
    "qf",
    "startuptime",
    "trouble",
  },
  callback = function(event)
    vim.bo[event.buf].buflisted = false
    vim.keymap.set("n", "q", "<cmd>close<CR>", {
      buffer = event.buf,
      silent = true,
      desc = "Close window",
    })
  end,
})

vim.api.nvim_create_autocmd("LspAttach", {
  group = augroup,
  desc = "Set LSP buffer keymaps",
  callback = function(event)
    local client = vim.lsp.get_client_by_id(event.data.client_id)
    require("config.lsp").on_attach(client, event.buf)
  end,
})

vim.api.nvim_create_autocmd("BufWritePre", {
  group = augroup,
  desc = "Create missing parent directories before writing",
  callback = function(event)
    if event.match:match("^%w%w+://") then
      return
    end

    local file = vim.uv.fs_realpath(event.match) or event.match
    vim.fn.mkdir(vim.fn.fnamemodify(file, ":p:h"), "p")
  end,
})

vim.api.nvim_create_autocmd("BufWinEnter", {
  group = augroup,
  desc = "Give neogit's commit editor a Commit button and an honest q",
  pattern = { "*/COMMIT_EDITMSG", "*/MERGE_MSG" },
  callback = function(event)
    -- Only neogit's editor, not a plain `git commit` run from a :terminal with
    -- EDITOR=nvim. Neogit hardcodes ZZ/ZQ (editor/init.lua:216-231), so a
    -- buffer-local ZZ is the discriminator. BufWinEnter is late enough to see
    -- them: Buffer.create sets its mappings at lib/buffer.lua:794 and only opens
    -- the window at ~806, which is what fires this event.
    local has_zz = false

    for _, map in ipairs(vim.api.nvim_buf_get_keymap(event.buf, "n")) do
      if map.lhs == "ZZ" then
        has_zz = true
        break
      end
    end

    if not has_zz then
      return
    end

    require("config.git").dress_commit_editor(event.buf, vim.api.nvim_get_current_win())
  end,
})

vim.api.nvim_create_autocmd({ "FocusGained", "TermClose", "TermLeave" }, {
  group = augroup,
  desc = "Reload files changed outside of Neovim",
  callback = function()
    if vim.o.buftype ~= "nofile" then
      vim.cmd("checktime")
    end
  end,
})

vim.api.nvim_create_autocmd("VimResized", {
  group = augroup,
  desc = "Equalize split sizes when the terminal is resized",
  callback = function()
    local tab = vim.fn.tabpagenr()
    vim.cmd("tabdo wincmd =")
    vim.cmd("tabnext " .. tab)
  end,
})
