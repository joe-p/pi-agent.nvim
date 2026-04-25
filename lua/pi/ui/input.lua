-- pi.nvim input buffer

local M = {}

local buf = nil
local win = nil
local opts = {}

-- Require modules directly to avoid circular deps
local rpc = require 'pi.rpc'
local session = require 'pi.session'

function M.setup(config)
  opts = config
end

function M.create()
  if buf and vim.api.nvim_buf_is_valid(buf) then
    return buf
  end

  -- Check if a buffer with this name already exists (e.g., from previous session)
  local existing_buf = vim.fn.bufexists('pi-input://input') ~= 0 and vim.fn.bufnr('pi-input://input') or -1
  if existing_buf ~= -1 and vim.api.nvim_buf_is_valid(existing_buf) then
    buf = existing_buf
  else
    buf = vim.api.nvim_create_buf(false, true)
    pcall(vim.api.nvim_buf_set_name, buf, 'pi-input://input')
    vim.api.nvim_set_option_value('filetype', 'piinput', { buf = buf })
    vim.api.nvim_set_option_value('buftype', 'acwrite', { buf = buf }) -- Allow writing
    vim.api.nvim_set_option_value('bufhidden', 'hide', { buf = buf })
    vim.api.nvim_set_option_value('swapfile', false, { buf = buf })
    vim.api.nvim_set_option_value('modifiable', true, { buf = buf })
  end

  -- Always set up keymaps (buffer-local keymaps need to be set each time)
  M.setup_keymaps()

  -- Prompt placeholder
  M.set_placeholder 'Type your message here...'

  return buf
end

function M.get_buf()
  return buf
end

function M.configure_window(win_id)
  win = win_id
  vim.api.nvim_set_option_value('winfixheight', true, { win = win_id })
  vim.api.nvim_set_option_value('number', false, { win = win_id })
  vim.api.nvim_set_option_value('relativenumber', false, { win = win_id })
  vim.api.nvim_set_option_value('signcolumn', 'no', { win = win_id })
  vim.api.nvim_set_option_value('cursorline', true, { win = win_id })
  -- Window-local display options
  vim.api.nvim_set_option_value('wrap', true, { win = win_id })
  vim.api.nvim_set_option_value('linebreak', true, { win = win_id })
  vim.api.nvim_set_option_value('breakindent', true, { win = win_id })
end

function M.setup_keymaps()
  -- Toggle with close keymap (default: q)
  local close_key = opts.keymaps and opts.keymaps.close or 'q'
  vim.api.nvim_buf_set_keymap(buf, 'n', close_key, '<cmd>PiToggle<CR>', { noremap = true, silent = true })

  -- Send message with Enter in normal mode
  vim.api.nvim_buf_set_keymap(buf, 'n', '<CR>', '', {
    noremap = true,
    silent = true,
    callback = function()
      M.send_message(false)
    end,
  })

  local send_steering_key = opts.keymaps and opts.keymaps.send_steering or '<S-CR>'
  -- Send steering message with Shift+Enter (or a different key for terminal compatibility)
  vim.api.nvim_buf_set_keymap(buf, 'i', send_steering_key, '', {
    noremap = true,
    silent = true,
    callback = function()
      M.send_message(true)
    end,
  })

  -- Also provide a command version for terminals without Shift+Enter
  vim.api.nvim_buf_set_keymap(buf, 'n', '<C-s>', '', {
    noremap = true,
    silent = true,
    callback = function()
      M.send_message(true)
    end,
  })

  -- Clear on <C-c>
  vim.api.nvim_buf_set_keymap(buf, 'n', '<C-c>', '', {
    noremap = true,
    silent = true,
    callback = function()
      M.clear()
    end,
  })

  -- Abort on double C-c
  vim.api.nvim_buf_set_keymap(buf, 'n', '<C-c><C-c>', '', {
    noremap = true,
    silent = true,
    callback = function()
      rpc.send { type = 'abort' }
    end,
  })

  -- @ file reference support
  vim.api.nvim_buf_set_keymap(buf, 'i', '@', '', {
    noremap = true,
    silent = true,
    callback = function()
      -- Insert @ and open file picker
      vim.api.nvim_feedkeys('@', 'ni', false)
      vim.defer_fn(function()
        M.open_file_picker()
      end, 100)
    end,
  })

  -- New session
  vim.api.nvim_buf_set_keymap(buf, 'n', '<C-n>', '', {
    noremap = true,
    silent = true,
    callback = function()
      rpc.send { type = 'new_session' }
      -- Clear chat via UI
      local ui = require 'pi.ui'
      ui.clear_chat()
    end,
  })

  -- File reference in normal mode
  vim.api.nvim_buf_set_keymap(buf, 'n', '@', '', {
    noremap = true,
    silent = true,
    callback = M.open_file_picker,
  })
end

function M.send_message(steering)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  -- Get all lines
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local text = table.concat(lines, '\n')

  -- Trim whitespace
  text = vim.trim(text)

  -- Don't send empty messages
  if text == '' then
    return
  end

  -- Build command
  local state = session.get_state()
  local cmd = {
    type = 'prompt',
    message = text,
  }

  -- Add streaming behavior if agent is busy
  if state and state.isStreaming then
    cmd.streamingBehavior = steering and 'steer' or 'followUp'
  end

  -- Send via RPC
  rpc.send(cmd)

  -- Add to UI
  local ui = require 'pi.ui'
  ui.add_user_message(text)

  -- Clear buffer
  M.clear()
end

function M.clear()
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
end

function M.set_placeholder(text)
  -- Can use virtual text for placeholder
  -- For now, just leave empty
end

function M.open_file_picker()
  -- Use built-in file picker or telescope/fzf if available
  local picker = M.get_picker()

  if picker == 'telescope' then
    require('telescope.builtin').find_files {
      attach_mappings = function(prompt_bufnr, map)
        local actions = require 'telescope.actions'
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = require('telescope.actions.state').get_selected_entry()
          if selection then
            M.insert_file_ref(selection.value)
          end
        end)
        return true
      end,
    }
  elseif picker == 'fzf-lua' then
    require('fzf-lua').files {
      actions = {
        ['default'] = function(selected)
          if selected then
            M.insert_file_ref(selected[1])
          end
        end,
      },
    }
  else
    -- Fallback to built-in
    vim.ui.select(vim.fn.glob('**/*', true, true), {
      prompt = 'Select file:',
    }, function(choice)
      if choice then
        M.insert_file_ref(choice)
      end
    end)
  end
end

function M.get_picker()
  -- Check for telescope
  local ok, _ = pcall(require, 'telescope')
  if ok then
    return 'telescope'
  end

  -- Check for fzf-lua
  ok, _ = pcall(require, 'fzf-lua')
  if ok then
    return 'fzf-lua'
  end

  -- Fallback to none
  return nil
end

function M.insert_file_ref(filepath)
  -- Get cursor position
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ''

  -- Insert @filepath after cursor
  local before = line:sub(1, col)
  local after = line:sub(col + 1)
  vim.api.nvim_buf_set_lines(buf, row - 1, row, false, { before .. '@' .. filepath .. after })
  vim.api.nvim_win_set_cursor(0, { row, col + 1 + #filepath })
end

function M.focus()
  -- Find window with input buffer and focus it
  for _, win_id in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win_id) == buf then
      vim.api.nvim_set_current_win(win_id)
      -- Enter insert mode
      vim.cmd 'startinsert'
      return
    end
  end
end

-- Get current content
function M.get_content()
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return ''
  end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  return table.concat(lines, '\n')
end

return M
