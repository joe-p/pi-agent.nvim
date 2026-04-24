-- pi.nvim chat buffer (output)

local M = {}

local buf = nil
local ns_id = vim.api.nvim_create_namespace 'pi-chat'
local opts = {}

-- Track thinking text position for highlighting
local thinking_active = false
local thinking_start_line = nil
local thinking_start_col = nil

function M.setup(config)
  opts = config
end

function M.create()
  -- Create buffer if doesn't exist
  if buf and vim.api.nvim_buf_is_valid(buf) then
    return buf
  end

  buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, 'pi-chat://chat')
  vim.api.nvim_set_option_value('filetype', 'pichat', { buf = buf })
  vim.api.nvim_set_option_value('buftype', 'nofile', { buf = buf })
  vim.api.nvim_set_option_value('bufhidden', 'hide', { buf = buf })
  vim.api.nvim_set_option_value('swapfile', false, { buf = buf })
  vim.api.nvim_set_option_value('modifiable', true, { buf = buf })

  local close_key = opts.keymaps and opts.keymaps.close or 'q'
  vim.api.nvim_buf_set_keymap(buf, 'n', close_key, '<cmd>PiToggle<CR>', { noremap = true, silent = true })

  return buf
end

function M.get_buf()
  return buf
end

function M.configure_window(win)
  vim.api.nvim_set_option_value('winfixheight', true, { win = win })
  vim.api.nvim_set_option_value('cursorline', false, { win = win })
  vim.api.nvim_set_option_value('number', false, { win = win })
  vim.api.nvim_set_option_value('relativenumber', false, { win = win })
  vim.api.nvim_set_option_value('signcolumn', 'no', { win = win })
  vim.api.nvim_set_option_value('wrap', true, { win = win })
  vim.api.nvim_set_option_value('linebreak', true, { win = win })
  vim.api.nvim_set_option_value('breakindent', true, { win = win })
end

function M.clear()
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
end

-- Render a message event from pi
function M.render_message(msg)
  local msg_type = msg.type

  if msg_type == 'agent_start' then
    M.append_spinner 'Thinking...'
  elseif msg_type == 'agent_end' then
    M.finish_spinner()
    -- Render final messages if available
    if msg.messages then
      for _, m in ipairs(msg.messages) do
        if m.errorMessage then
          vim.notify('pi-agent ERROR: ' .. m.errorMessage, vim.log.levels.ERROR)
          M.append_error(m.errorMessage)
        end
      end
    end
  elseif msg_type == 'message_start' then
  elseif msg_type == 'message_update' then
    M.handle_message_update(msg)
  elseif msg_type == 'message_end' then
    M.finish_thinking()
    M.append_newline()
  elseif msg_type == 'tool_execution_start' then
    M.append_tool_start(msg.toolName, msg.args)
  elseif msg_type == 'tool_execution_update' then
    M.update_tool_output(msg.toolCallId, msg.partialResult)
  elseif msg_type == 'tool_execution_end' then
    M.append_tool_end(msg.toolCallId, msg.result, msg.isError)
  elseif msg_type == 'error' or msg_type == 'extension_error' then
    M.append_error(msg.error or 'Unknown error')
  elseif msg_type == 'compaction_start' then
    M.append_info 'Compacting conversation...'
  elseif msg_type == 'compaction_end' then
    M.append_info 'Compaction complete'
  elseif msg_type == 'queue_update' then
    -- Optionally show queue status
    -- M.append_info('Queue: ' .. tostring(#(msg.steering or {})) .. ' steering, ' .. tostring(#(msg.followUp or {})) .. ' followUp')
  elseif msg_type == 'extension_ui_request' then
    -- Handle extension UI requests
    require('pi.extension_ui').handle_request(msg)
  end
end

function M.handle_message_update(msg)
  local event = msg.assistantMessageEvent
  if not event then
    vim.notify('non-event: ' .. vim.inspect(msg))
    return
  end

  local event_type = event.type

  if event_type == 'text_delta' then
    M.append_text(event.delta)
  elseif event_type == 'thinking_delta' then
    M.append_thinking(event.delta)
  elseif event_type == 'toolcall_start' then
    M.append_toolcall_start(event.partial)
  elseif event_type == 'toolcall_delta' then
    M.append_toolcall_delta(event.delta)
  elseif event_type == 'toolcall_end' then
    M.append_toolcall_end(event.toolCall)
  elseif event_type == 'text_start' then
    -- no-op, handled in delta
  elseif event_type == 'text_end' then
    -- no-op, handled in delta
  elseif event_type == 'thinking_start' then
    -- no-op, handled in delta
  elseif event_type == 'thinking_end' then
    -- no-op, handled in delta
  else
    vim.notify('[pi-agent]: unknown event type: ' .. event_type .. ' ' .. vim.inspect(event), vim.log.levels.WARN)
  end
end

function M.add_user_message(text)
  local lines = {
    '',
    '┌─ User ────────────────────────────────────────────────────',
    '│',
  }

  -- Split text into lines and indent
  for _, line in ipairs(vim.split(text, '\n', { plain = true })) do
    table.insert(lines, '│ ' .. line)
  end

  table.insert(lines, '│')
  table.insert(
    lines,
    '└─────────────────────────────────────────────────────────────'
  )
  table.insert(lines, '')

  M.append_lines(lines)
end

function M.append_text(text)
  if not text or text == '' then
    return
  end

  -- Finish thinking if we're switching to regular text
  if thinking_active then
    M.finish_thinking()
  end

  -- Handle newlines in the text
  if text:find '\n' then
    -- Split text by newlines
    local parts = vim.split(text, '\n', { plain = true })

    -- Get the last line
    local line_count = vim.api.nvim_buf_line_count(buf)
    local last_line = vim.api.nvim_buf_get_lines(buf, line_count - 1, line_count, false)[1] or ''

    -- First part appends to current line
    local lines_to_set = { last_line .. parts[1] }

    -- Add remaining parts as new lines
    for i = 2, #parts do
      table.insert(lines_to_set, parts[i])
    end

    vim.api.nvim_buf_set_lines(buf, line_count - 1, line_count, false, lines_to_set)
  else
    -- Simple append without newlines
    local line_count = vim.api.nvim_buf_line_count(buf)
    local last_line = vim.api.nvim_buf_get_lines(buf, line_count - 1, line_count, false)[1] or ''

    vim.api.nvim_buf_set_lines(buf, line_count - 1, line_count, false, { last_line .. text })
  end
end

function M.append_thinking(text)
  if not text or text == '' then
    return
  end

  -- Handle the start of thinking block
  if not thinking_active then
    local line_count = vim.api.nvim_buf_line_count(buf)
    local last_line = vim.api.nvim_buf_get_lines(buf, line_count - 1, line_count, false)[1] or ''

    -- Start fresh - if last line isn't empty, add indicator on new line
    if last_line ~= '' then
      M.append_lines { '' }
      line_count = line_count + 1
    end

    -- Show thinking indicator
    M.append_lines { '(*thinking*) ' }

    -- Track where thinking content starts (after indicator)
    thinking_start_line = line_count
    thinking_start_col = 13 -- length of "(*thinking*) "
    thinking_active = true
  end

  -- Get position before appending
  local line_count = vim.api.nvim_buf_line_count(buf)
  local last_line = vim.api.nvim_buf_get_lines(buf, line_count - 1, line_count, false)[1] or ''

  -- Handle newlines in thinking text
  if text:find '\n' then
    local parts = vim.split(text, '\n', { plain = true })
    local lines_to_set = { last_line .. parts[1] }
    for i = 2, #parts do
      table.insert(lines_to_set, parts[i])
    end
    vim.api.nvim_buf_set_lines(buf, line_count - 1, line_count, false, lines_to_set)
  else
    -- Simple append
    vim.api.nvim_buf_set_lines(buf, line_count - 1, line_count, false, { last_line .. text })
  end

  -- Apply PiThinking highlight to all thinking content
  local new_line_count = vim.api.nvim_buf_line_count(buf)
  for i = thinking_start_line, new_line_count - 1 do
    if i == thinking_start_line then
      vim.api.nvim_buf_add_highlight(buf, ns_id, 'PiThinking', i, thinking_start_col, -1)
    else
      vim.api.nvim_buf_add_highlight(buf, ns_id, 'PiThinking', i, 0, -1)
    end
  end
end

function M.finish_thinking()
  if thinking_active then
    -- Add blank line after thinking ends
    M.append_lines { '', '' }
    thinking_active = false
    thinking_start_line = nil
    thinking_start_col = nil
  end
end

function M.append_newline()
  M.append_lines { '' }
end

function M.append_lines(lines)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local line_count = vim.api.nvim_buf_line_count(buf)
  vim.api.nvim_buf_set_lines(buf, line_count, line_count, false, lines)

  -- Scroll to bottom
  M.scroll_to_bottom()
end

function M.scroll_to_bottom()
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  -- Find window displaying this buffer and scroll it
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == buf then
      local line_count = vim.api.nvim_buf_line_count(buf)
      vim.api.nvim_win_set_cursor(win, { line_count, 0 })
    end
  end
end

function M.append_spinner(text)
  -- Start a timer to animate spinner
  -- (Simplified for now)
  M.append_lines { '', '> ' .. text, '' }
end

function M.finish_spinner()
  -- Stop spinner animation
end

function M.append_tool_start(toolName, args)
  local header = string.format('╭─ Tool: %s ────', toolName)
  local lines = { '', header }

  -- Show args
  if args then
    local args_str = vim.json.encode(args)
    table.insert(lines, '│ ' .. args_str)
  end

  table.insert(lines, '')

  M.append_lines(lines)
end

function M.append_tool_end(_, result, isError)
  local lines = { '│' }

  if result and result.content then
    for _, content in ipairs(result.content) do
      if content.type == 'text' then
        for _, line in ipairs(vim.split(content.text, '\n', { plain = true })) do
          table.insert(lines, '│ ' .. line)
        end
      end
    end
  end

  table.insert(lines, string.format('╰─── %s ────', isError and 'Error' or 'End'))
  table.insert(lines, '')

  M.append_lines(lines)
end

function M.append_error(err)
  local lines = {
    '',
    '┌─ Error ─────────────────────────────────────────────────────',
    '│ ' .. err,
    '└─────────────────────────────────────────────────────────────',
    '',
  }
  M.append_lines(lines)
end

function M.append_info(info)
  local lines = {
    '',
    '-- ' .. info .. ' --',
    '',
  }
  M.append_lines(lines)
end

function M.append_toolcall_end(toolCall)
  local lines = {
    '',
    string.format('╭─ Calling: %s ────', toolCall.name),
    '│ ' .. vim.json.encode(toolCall.arguments),
    '└────────────────────────────────────────────────────────────────',
    '',
  }
  M.append_lines(lines)
end

return M
