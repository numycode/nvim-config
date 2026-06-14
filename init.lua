local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  -- Clone lazy.nvim from its stable branch
  vim.fn.system({
    "git", "clone", "--filter=blob:none",
    "--branch=stable",
    "https://github.com/folke/lazy.nvim.git",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)        -- add to runtimepath
-- Set leader keys before loading plugins:
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"
-- Load lazy.nvim
require("lazy").setup({
  spec = {
    { "wakatime/vim-wakatime", lazy = false },
  },
  install = { colorscheme = { "habamax" } },  -- optional
  checker = { enabled = true },               -- automatic updates
})
