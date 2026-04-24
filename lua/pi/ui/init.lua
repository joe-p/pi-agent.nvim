-- pi.nvim UI module
-- Simple layout: chat + input stacked vertically on the right

local M = {}

local chat = require 'pi.ui.chat'
local input = require 'pi.ui.input'

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

  -- Create the layout: chat+input on the right
  M.create_right_windows()

  -- Initialize buffers
  chat.create()
  input.create()

  -- Bind buffers to windows
  M.bind_buffers()

  -- Focus input window
  input.focus()
end

function M.create_right_windows()
  -- Save original window
  local original_win = vim.api.nvim_get_current_win()

  -- Calculate sizes
  local height = vim.o.lines
  local width = vim.o.columns

  -- How much width to use on the right
  local right_width = math.floor(width * (opts.chat_width or 0.45))

  -- Chat gets most of the height, input gets the rest
  local chat_height = math.floor(height * (opts.chat_height_ratio or 0.75))

  -- Create vertical split on the RIGHT
  vim.cmd(string.format('botright %dvsplit', right_width))

  -- Now we're in the right panel
  -- Split it horizontally: chat on top, input on bottom
  vim.cmd(string.format('aboveleft %dsplit', chat_height))
  windows.chat = vim.api.nvim_get_current_win()

  -- Input window is below
  vim.cmd 'wincmd j'
  windows.input = vim.api.nvim_get_current_win()

  -- Go back to original window (left side)
  vim.api.nvim_set_current_win(original_win)
end

function M.bind_buffers()
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
