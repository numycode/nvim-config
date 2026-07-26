-- Plugin-owned keymaps live with their specs in lua/plugins/. This file holds
-- the ones that do not depend on a plugin being loaded.
local keymap = vim.keymap.set

local function opts(desc)
  return { desc = desc, silent = true }
end

local function diagnostic_jump(count)
  if vim.diagnostic.jump then
    return function()
      vim.diagnostic.jump({ count = count, float = true })
    end
  end

  return count > 0 and vim.diagnostic.goto_next or vim.diagnostic.goto_prev
end

keymap("n", "<Esc>", "<cmd>nohlsearch<CR>", opts("Clear search highlight"))
keymap("n", "<leader>w", "<cmd>write<CR>", opts("Save file"))
keymap("n", "<leader>q", "<cmd>quit<CR>", opts("Quit window"))
keymap("n", "<leader>Q", "<cmd>qall<CR>", opts("Quit all"))

keymap("n", "<C-h>", "<C-w>h", opts("Move to left window"))
keymap("n", "<C-j>", "<C-w>j", opts("Move to lower window"))
keymap("n", "<C-k>", "<C-w>k", opts("Move to upper window"))
keymap("n", "<C-l>", "<C-w>l", opts("Move to right window"))

-- Window management
keymap("n", "<leader>-", "<C-w>s", opts("Split window below"))
keymap("n", "<leader>|", "<C-w>v", opts("Split window right"))

-- Buffers. <leader>bd is owned by snacks (it preserves the window layout);
-- <S-h>/<S-l> come from bufferline.
keymap("n", "<leader>bn", "<cmd>bnext<CR>", opts("Next buffer"))
keymap("n", "<leader>bb", "<cmd>edit #<CR>", opts("Alternate buffer"))

-- Diagnostics. The line float moved from <leader>e to <leader>cd, because
-- <leader>e is now the file explorer.
keymap("n", "]d", diagnostic_jump(1), opts("Next diagnostic"))
keymap("n", "[d", diagnostic_jump(-1), opts("Previous diagnostic"))
keymap("n", "]e", function()
  vim.diagnostic.jump({ count = 1, severity = vim.diagnostic.severity.ERROR, float = true })
end, opts("Next error"))
keymap("n", "[e", function()
  vim.diagnostic.jump({ count = -1, severity = vim.diagnostic.severity.ERROR, float = true })
end, opts("Previous error"))
keymap("n", "<leader>cd", vim.diagnostic.open_float, opts("Line diagnostics"))
keymap("n", "<leader>xl", vim.diagnostic.setloclist, opts("Diagnostics to loclist"))

-- Keep the cursor centred while scrolling and searching.
keymap("n", "<C-d>", "<C-d>zz", opts("Scroll down"))
keymap("n", "<C-u>", "<C-u>zz", opts("Scroll up"))
keymap("n", "n", "nzzzv", opts("Next search result"))
keymap("n", "N", "Nzzzv", opts("Previous search result"))

keymap("v", "<", "<gv", opts("Indent left"))
keymap("v", ">", ">gv", opts("Indent right"))
keymap("v", "J", ":m '>+1<CR>gv=gv", opts("Move selection down"))
keymap("v", "K", ":m '<-2<CR>gv=gv", opts("Move selection up"))

-- Paste over a selection without clobbering the unnamed register.
keymap("v", "p", '"_dP', opts("Paste without yanking"))
