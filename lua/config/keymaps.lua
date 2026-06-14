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

keymap("n", "<C-h>", "<C-w>h", opts("Move to left window"))
keymap("n", "<C-j>", "<C-w>j", opts("Move to lower window"))
keymap("n", "<C-k>", "<C-w>k", opts("Move to upper window"))
keymap("n", "<C-l>", "<C-w>l", opts("Move to right window"))

keymap("n", "<leader>bn", "<cmd>bnext<CR>", opts("Next buffer"))
keymap("n", "<leader>bp", "<cmd>bprevious<CR>", opts("Previous buffer"))
keymap("n", "<leader>bd", "<cmd>bdelete<CR>", opts("Delete buffer"))

keymap("n", "]d", diagnostic_jump(1), opts("Next diagnostic"))
keymap("n", "[d", diagnostic_jump(-1), opts("Previous diagnostic"))
keymap("n", "<leader>e", vim.diagnostic.open_float, opts("Show line diagnostic"))
keymap("n", "<leader>xl", vim.diagnostic.setloclist, opts("Diagnostics loclist"))

keymap("v", "<", "<gv", opts("Indent left"))
keymap("v", ">", ">gv", opts("Indent right"))
keymap("v", "J", ":m '>+1<CR>gv=gv", opts("Move selection down"))
keymap("v", "K", ":m '<-2<CR>gv=gv", opts("Move selection up"))
