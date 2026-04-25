-- pi.nvim Extension UI Protocol handler
-- Handles select, confirm, input, editor, notify, setStatus, setWidget, setTitle

local M = {}

-- Track pending UI requests
local pending_requests = {}

-- Handle extension_ui_request from pi
function M.handle_request(msg)
  local method = msg.method
  local id = msg.id

  -- Fire-and-forget methods
  if method == 'notify' then
    local chat = require 'pi.ui.chat'
    chat.append_content_with_header('Notify', msg.message)
    return
  end

  if method == 'setStatus' then
    -- Could integrate with statusline
    -- vim.notify('Status: ' .. (msg.statusText or 'clear'), vim.log.levels.INFO)
    return
  end

  if method == 'setWidget' then
    -- Show widget in UI
    M.show_widget(msg.widgetKey, msg.widgetLines, msg.widgetPlacement)
    return
  end

  if method == 'setTitle' then
    vim.cmd('set title titlestring=' .. vim.fn.fnameescape(msg.title))
    return
  end

  if method == 'set_editor_text' then
    -- Set text in input buffer
    local input = require 'pi.ui.input'
    if input.get_buf() then
      vim.api.nvim_buf_set_lines(input.get_buf(), 0, -1, false, vim.split(msg.text, '\n', { plain = true }))
    end
    return
  end

  -- Dialog methods (need response)
  if method == 'select' then
    M.handle_select(id, msg)
  elseif method == 'confirm' then
    M.handle_confirm(id, msg)
  elseif method == 'input' then
    M.handle_input(id, msg)
  elseif method == 'editor' then
    M.handle_editor(id, msg)
  end
end

function M.get_log_level(notify_type)
  if notify_type == 'warning' then
    return vim.log.levels.WARN
  elseif notify_type == 'error' then
    return vim.log.levels.ERROR
  else
    return vim.log.levels.INFO
  end
end

function M.handle_select(id, msg)
  vim.ui.select(msg.options, {
    prompt = msg.title,
  }, function(choice)
    M.send_response(id, choice and { value = choice } or { cancelled = true })
  end)
end

function M.handle_confirm(id, msg)
  vim.ui.input({
    prompt = msg.title .. ' (y/n): ',
  }, function(input)
    if input == nil then
      M.send_response(id, { cancelled = true })
    else
      M.send_response(id, { confirmed = input:lower() == 'y' or input:lower() == 'yes' })
    end
  end)
end

function M.handle_input(id, msg)
  vim.ui.input({
    prompt = msg.title .. ': ',
    default = '',
  }, function(input)
    if input == nil then
      M.send_response(id, { cancelled = true })
    else
      M.send_response(id, { value = input })
    end
  end)
end

function M.handle_editor(id, msg)
  -- Open a temp buffer for editing
  local temp_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(temp_buf, 'pi://extension-editor')

  if msg.prefill then
    vim.api.nvim_buf_set_lines(temp_buf, 0, -1, false, vim.split(msg.prefill, '\n', { plain = true }))
  end

  -- Open in a new split
  vim.cmd 'topleft split'
  local edit_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(edit_win, temp_buf)

  -- Set up autocmd for when buffer is closed
  vim.api.nvim_create_autocmd('BufDelete', {
    buffer = temp_buf,
    callback = function()
      -- Get content before closing
      if vim.api.nvim_buf_is_valid(temp_buf) then
        local lines = vim.api.nvim_buf_get_lines(temp_buf, 0, -1, false)
        local text = table.concat(lines, '\n')

        -- Only send if window was closed normally (not cancelled)
        -- This is a simplification - proper handling would use a keymap
        if vim.api.nvim_win_is_valid(edit_win) then
          vim.api.nvim_win_close(edit_win, true)
        end

        M.send_response(id, { value = text })
      end
    end,
    once = true,
  })

  -- Set up keymaps for submission
  vim.api.nvim_buf_set_keymap(temp_buf, 'n', '<CR>', '', {
    noremap = true,
    silent = true,
    callback = function()
      local lines = vim.api.nvim_buf_get_lines(temp_buf, 0, -1, false)
      local text = table.concat(lines, '\n')

      vim.api.nvim_win_close(edit_win, true)
      vim.api.nvim_buf_delete(temp_buf, { force = true })

      M.send_response(id, { value = text })
    end,
  })

  vim.api.nvim_buf_set_keymap(temp_buf, 'n', '<C-c>', '', {
    noremap = true,
    silent = true,
    callback = function()
      vim.api.nvim_win_close(edit_win, true)
      vim.api.nvim_buf_delete(temp_buf, { force = true })
      M.send_response(id, { cancelled = true })
    end,
  })
end

function M.show_widget(key, lines, placement)
  -- Could show widget above/below editor
  -- For now, just show in messages
  if lines then
    vim.notify('Widget [' .. key .. '] (' .. (placement or 'above') .. '):\n' .. table.concat(lines, '\n'), vim.log.levels.INFO)
  else
    vim.notify('Widget [' .. key .. '] cleared', vim.log.levels.INFO)
  end
end

function M.send_response(id, response)
  local rpc = require 'pi.rpc'

  response.type = 'extension_ui_response'
  response.id = id

  rpc.send(response)
end

return M
