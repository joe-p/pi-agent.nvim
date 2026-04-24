-- pi.nvim UI module

local M = {}

local chat = require('pi.ui.chat')
local input = require('pi.ui.input')

local opts = {}
local windows = {}

function M.setup(config)
  opts = config
  chat.setup(config)
  input.setup(config)
end

function M.create_windows()
  -- Close existing windows
  M.close()
  
  local layout = opts.layout or 'horizontal'
  
  if layout == 'horizontal' then
    M.create_horizontal_layout()
  elseif layout == 'vertical' then
    M.create_vertical_layout()
  else
    M.create_tab_layout()
  end
  
  -- Initialize buffers
  chat.create()
  input.create()
  
  -- Set up the windows
  M.arrange_windows(layout)
  
  -- Focus input window
  input.focus()
end

function M.create_horizontal_layout()
  -- Save original window
  local original_win = vim.api.nvim_get_current_win()
  
  -- Calculate sizes
  local height = vim.o.lines
  local width = vim.o.columns
  local chat_height = math.floor(height * (opts.chat_height or 0.7))
  local input_height = math.min(opts.input_height or 3, height - chat_height - 2)
  
  -- Create chat window (top)
  vim.cmd(string.format('botright %dsplit', chat_height))
  windows.chat = vim.api.nvim_get_current_win()
  
  -- Create input window (bottom)
  vim.cmd(string.format('%dsplit', input_height))
  windows.input = vim.api.nvim_get_current_win()
  
  -- Go back to original window
  vim.api.nvim_set_current_win(original_win)
end

function M.create_vertical_layout()
  -- Save original window
  local original_win = vim.api.nvim_get_current_win()
  
  -- Calculate sizes
  local width = vim.o.columns
  local chat_width = math.floor(width * (opts.chat_width or 0.5))
  local input_width = width - chat_width
  
  -- Create chat window (left)
  vim.cmd(string.format('topleft %dvsplit', chat_width))
  windows.chat = vim.api.nvim_get_current_win()
  
  -- Create input window (right, same height as chat)
  vim.cmd('wincmd l')
  windows.input = vim.api.nvim_get_current_win()
  
  -- Go back to original window
  vim.api.nvim_set_current_win(original_win)
end

function M.create_tab_layout()
  -- Create chat window in new tab
  vim.cmd('tabnew')
  windows.chat = vim.api.nvim_get_current_win()
  
  -- Create input window at bottom
  vim.cmd(string.format('botright %dsplit', opts.input_height or 3))
  windows.input = vim.api.nvim_get_current_win()
end

function M.arrange_windows(layout)
  -- Set buffer to windows
  if windows.chat then
    vim.api.nvim_win_set_buf(windows.chat, chat.get_buf())
    chat.configure_window(windows.chat)
  end
  
  if windows.input then
    vim.api.nvim_win_set_buf(windows.input, input.get_buf())
    input.configure_window(windows.input)
  end
end

function M.close()
  -- Close windows but keep buffers
  if windows.chat then
    pcall(vim.api.nvim_win_close, windows.chat, true)
  end
  if windows.input then
    pcall(vim.api.nvim_win_close, windows.input, true)
  end
  windows = {}
end

function M.is_open()
  return windows.chat ~= nil and vim.api.nvim_win_is_valid(windows.chat)
end

-- Delegate to chat module
function M.render_message(msg)
  chat.render_message(msg)
end

function M.add_user_message(text)
  chat.add_user_message(text)
end

function M.clear_chat()
  chat.clear()
end

return M