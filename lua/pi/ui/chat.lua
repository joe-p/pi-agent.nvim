-- pi.nvim chat buffer (output)

local M = {}

local buf = nil
local ns_id = vim.api.nvim_create_namespace('pi-chat')
local opts = {}

-- Message store for rendering
local pending_deltas = {}
local current_message_ns = nil

-- Track thinking text position for highlighting
local thinking_extmark = nil

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
  
  -- (Window-local options set in configure_window)
  
  -- Keymaps
  vim.api.nvim_buf_set_keymap(buf, 'n', 'q', ':q', { noremap = true, silent = true })
  
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
  pending_deltas = {}
end

-- Render a message event from pi
function M.render_message(msg)
  local msg_type = msg.type
  
  if msg_type == 'agent_start' then
    M.append_spinner('Thinking...')
    
  elseif msg_type == 'agent_end' then
    M.finish_spinner()
    -- Render final messages if available
    if msg.messages then
      M.render_message_history(msg.messages)
    end
    
  elseif msg_type == 'message_start' then
    current_message_ns = vim.api.nvim_create_namespace('pi-message-' .. vim.fn.localtime())
    
  elseif msg_type == 'message_update' then
    M.handle_message_update(msg)
    
  elseif msg_type == 'message_end' then
    M.finish_thinking()
    M.append_newline()
    current_message_ns = nil
    
  elseif msg_type == 'tool_execution_start' then
    M.append_tool_start(msg.toolName, msg.args)
    
  elseif msg_type == 'tool_execution_update' then
    M.update_tool_output(msg.toolCallId, msg.partialResult)
    
  elseif msg_type == 'tool_execution_end' then
    M.append_tool_end(msg.toolCallId, msg.result, msg.isError)
    
  elseif msg_type == 'error' or msg_type == 'extension_error' then
    M.append_error(msg.error or 'Unknown error')
    
  elseif msg_type == 'compaction_start' then
    M.append_info('Compacting conversation...')
    
  elseif msg_type == 'compaction_end' then
    M.append_info('Compaction complete')
    
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
  if not event then return end
  
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
  table.insert(lines, '└─────────────────────────────────────────────────────────────')
  table.insert(lines, '')
  
  M.append_lines(lines)
end

function M.append_text(text)
  if not text or text == '' then return end
  
  -- Handle newlines in the text
  if text:find('\n') then
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
  if not text or text == '' then return end

  -- Handle the start of thinking block
  if not thinking_extmark then
    local line_count = vim.api.nvim_buf_line_count(buf)
    local last_line = vim.api.nvim_buf_get_lines(buf, line_count - 1, line_count, false)[1] or ''
    
    -- If last line has content, start a new line
    if last_line ~= '' then
      vim.api.nvim_buf_set_lines(buf, line_count, line_count, false, { '' })
      line_count = line_count + 1
    end
    
    -- Create extmark for the thinking text
    local opts = {
      virt_text = { { '(*thinking*) ', 'PiThinking' } },
      virt_text_pos = 'inline',
    }
    thinking_extmark = vim.api.nvim_buf_set_extmark(buf, ns_id, line_count - 1, 0, opts)
  end
  
  -- Get current position and append text
  local start_pos = vim.api.nvim_buf_get_extmark_by_id(buf, ns_id, thinking_extmark, {})
  local start_line = start_pos[1]
  local col = start_pos[2]
  
  -- Handle newlines in thinking text
  if text:find('\n') then
    local parts = vim.split(text, '\n', { plain = true })
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
    -- Simple append
    local line_count = vim.api.nvim_buf_line_count(buf)
    local last_line = vim.api.nvim_buf_get_lines(buf, line_count - 1, line_count, false)[1] or ''
    vim.api.nvim_buf_set_lines(buf, line_count - 1, line_count, false, { last_line .. text })
  end
  
  -- Apply PiThinking highlight to the new text
  local new_line_count = vim.api.nvim_buf_line_count(buf)
  local end_line = new_line_count - 1
  local end_col = #(vim.api.nvim_buf_get_lines(buf, end_line, end_line + 1, false)[1] or '')
  
  -- Highlight the range
  vim.api.nvim_buf_add_highlight(buf, ns_id, 'PiThinking', start_line, col, -1)
  if end_line > start_line then
    for i = start_line + 1, end_line do
      vim.api.nvim_buf_add_highlight(buf, ns_id, 'PiThinking', i, 0, -1)
    end
  end
end

function M.finish_thinking()
  -- Add a newline after thinking is done and clear the extmark tracker
  if thinking_extmark then
    M.append_newline()
    M.append_newline()
    thinking_extmark = nil
  end
end

function M.append_newline()
  M.append_lines({''})
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
  M.append_lines({ '', '> ' .. text, '' })
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

function M.update_tool_output(toolCallId, partialResult)
  -- Update the output for this tool call
  -- (More complex - would need to track extmarks per tool)
end

function M.append_tool_end(toolCallId, result, isError)
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

function M.append_toolcall_start(partial)
  -- Start of tool call
end

function M.append_toolcall_delta(delta)
  -- Tool call building
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

function M.render_message_history(messages)
  -- Render complete message history (used on agent_end)
  -- Could re-render everything for consistency
end

return M