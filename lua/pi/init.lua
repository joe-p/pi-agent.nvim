-- pi.nvim - Neovim plugin for pi coding agent
-- Main entry point

local M = {}

local config = require 'pi.config'
local rpc = require 'pi.rpc'
local ui = require 'pi.ui'
local session = require 'pi.session'

-- Default configuration
M.defaults = {
  -- Path to pi binary
  pi_cmd = 'pi',
  -- RPC mode options
  provider = nil,
  model = nil,
  no_session = false,
  session_dir = nil,
  -- UI options
  chat_width = 0.45, -- percentage of screen width for right panel
  chat_height_ratio = 0.75, -- percentage of height for chat within right panel (input gets rest)
  -- Keymaps
  keymaps = {
    send = { 'i', { noremap = true, silent = true }, { desc = 'Send message' } },
    send_steering = { 'S-CR', { noremap = true, silent = true }, { desc = 'Send steering message' } },
    abort = { 'C-c', { noremap = true, silent = true }, { desc = 'Abort' } },
    new_session = { 'C-n', { noremap = true, silent = true }, { desc = 'New session' } },
  },
}

function M.setup(opts)
  M.opts = vim.tbl_deep_extend('force', M.defaults, opts or {})
  config.setup(M.opts)

  -- Create commands
  vim.api.nvim_create_user_command('PiStart', function()
    M.start()
  end, { desc = 'Start pi agent' })

  vim.api.nvim_create_user_command('PiStop', function()
    M.stop()
  end, { desc = 'Stop pi agent' })

  vim.api.nvim_create_user_command('PiNew', function()
    M.new_session()
  end, { desc = 'New session' })

  vim.api.nvim_create_user_command('PiAbort', function()
    M.abort()
  end, { desc = 'Abort current operation' })

  vim.api.nvim_create_user_command('PiChat', function()
    M.open_chat()
  end, { desc = 'Open pi chat' })

  vim.api.nvim_create_user_command('PiToggle', function()
    M.toggle()
  end, { desc = 'Toggle pi chat and input windows' })
end

function M.start()
  if rpc.is_running() then
    vim.notify('pi is already running', vim.log.levels.WARN)
    return
  end

  -- Build command
  local cmd = { M.opts.pi_cmd, '--mode', 'rpc' }

  if M.opts.provider then
    table.insert(cmd, '--provider')
    table.insert(cmd, M.opts.provider)
  end

  if M.opts.model then
    table.insert(cmd, '--model')
    table.insert(cmd, M.opts.model)
  end

  if M.opts.no_session then
    table.insert(cmd, '--no-session')
  end

  if M.opts.session_dir then
    table.insert(cmd, '--session-dir')
    table.insert(cmd, M.opts.session_dir)
  end

  -- Debug: show command
  vim.notify('Starting: ' .. table.concat(cmd, ' '), vim.log.levels.INFO)

  -- Initialize UI
  ui.setup(M.opts)
  ui.create_windows()

  -- Start RPC
  rpc.start(cmd, {
    on_message = function(msg)
      session.handle_message(msg)
      ui.render_message(msg)
    end,
    on_error = function(err)
      vim.notify('pi error: ' .. err, vim.log.levels.ERROR)
    end,
  })

  -- Get initial state
  rpc.send { type = 'get_state' }
end

function M.stop()
  rpc.stop()
  ui.close()
end

function M.new_session()
  rpc.send { type = 'new_session' }
  ui.clear_chat()
end

function M.abort()
  rpc.send { type = 'abort' }
end

function M.open_chat()
  if not ui.is_open() then
    ui.create_windows()
  end
end

function M.toggle()
  if ui.is_open() then
    ui.close()
  else
    ui.create_windows()
  end
end

function M.send_message(text, opts)
  opts = opts or {}

  local state = session.get_state()
  local cmd = {
    type = 'prompt',
    message = text,
  }

  -- Add streaming behavior if agent is busy
  if state and state.isStreaming then
    cmd.streamingBehavior = opts.steering and 'steer' or 'followUp'
  end

  -- Send command
  rpc.send(cmd)

  -- Add to UI immediately
  ui.add_user_message(text)
end

return M
