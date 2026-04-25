-- pi.nvim plugin bootstrap
-- This file is loaded when Neovim starts

-- Ensure pi module is loaded
if not _G.pi_loaded then
  _G.pi_loaded = true

  -- Set up autocommands for filetypes
  vim.api.nvim_create_autocmd('FileType', {
    pattern = 'pichat',
    callback = function()
      -- Chat buffer options
      vim.opt_local.cursorline = false
      vim.opt_local.number = false
      vim.opt_local.relativenumber = false
      vim.opt_local.signcolumn = 'no'
      vim.opt_local.wrap = true
      vim.opt_local.linebreak = true
    end,
  })

  vim.api.nvim_create_autocmd('FileType', {
    pattern = 'piinput',
    callback = function()
      -- Input buffer options
      vim.opt_local.number = false
      vim.opt_local.relativenumber = false
      vim.opt_local.signcolumn = 'no'
      vim.opt_local.wrap = true
      vim.opt_local.linebreak = true
    end,
  })

  -- Prevent pi buffers from blocking :q with "no write since last change"
  if vim.fn.exists('##BufModifiedSet') == 1 then
    vim.api.nvim_create_autocmd('BufModifiedSet', {
      group = vim.api.nvim_create_augroup('PiNoModified', { clear = true }),
      callback = function(args)
        local ft = vim.bo[args.buf].filetype
        if ft == 'pichat' or ft == 'piinput' then
          vim.bo[args.buf].modified = false
        end
      end,
    })
  end

  -- Create highlight groups
  vim.api.nvim_set_hl(0, 'PiUser', { fg = '#7aa2f7', bold = true })
  vim.api.nvim_set_hl(0, 'PiAssistant', { fg = '#9ece6a', bold = true })
  vim.api.nvim_set_hl(0, 'PiTool', { fg = '#bb9af7', bold = true })
  vim.api.nvim_set_hl(0, 'PiError', { fg = '#f7768e' })
  vim.api.nvim_set_hl(0, 'PiThinking', { fg = '#565f89', italic = true })
end
