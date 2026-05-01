-- Test config for pi.nvim
-- Add this to your Neovim config path or use
-- nvim -u /path/to/pi.nvim/init.lua

-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath 'data' .. '/lazy/lazy.nvim'
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system {
    'git',
    'clone',
    '--filter=blob:none',
    'https://github.com/folke/lazy.nvim.git',
    '--branch=stable',
    lazypath,
  }
end
vim.opt.rtp:prepend(lazypath)

-- Add pi.nvim to runtime path
vim.opt.rtp:prepend(vim.fn.getcwd())

require('lazy').setup {
  {
    dir = vim.fn.getcwd(),
    name = 'pi-agent',
    config = function()
      require('pi-agent').setup {
        layout = 'horizontal',
        chat_height = 0.75,
        input_height = 3,
      }
    end,
  },

}

-- Quick keymap to start
vim.keymap.set('n', 'C-p', function()
  require('pi-agent').start()
end, { desc = 'Start pi chat' })

-- Set up basic options
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.expandtab = true
vim.opt.shiftwidth = 2
vim.opt.tabstop = 2
