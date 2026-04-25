-- pi.nvim chat buffer (output)

local M = {}

local buf = nil
local opts = {}

local line_width = 63
local diff_ns = vim.api.nvim_create_namespace 'pi_chat_diff'

-- Map of tool names to renderer descriptor tables.
-- Each descriptor has:
--   call   = function(ctx)   -- ctx: { chat, toolCall }
--   result = function(ctx)   -- ctx: { chat, toolCallId, result, isError }
M.tool_renderers = {}

-- Tracks tool call IDs that have an active custom renderer.
-- Maps toolCallId -> renderer descriptor.
local active_renderers = {}

function M.register_tool_renderer(tool_name, descriptor)
  M.tool_renderers[tool_name] = descriptor
end

function M.setup(config)
  opts = config
end

function M.create()
  -- Create buffer if doesn't exist
  if buf and vim.api.nvim_buf_is_valid(buf) then
    return buf
  end

  -- Check if a buffer with this name already exists (e.g., from previous session)
  local existing_buf = vim.fn.bufexists 'pi-chat://chat' ~= 0 and vim.fn.bufnr 'pi-chat://chat' or -1
  if existing_buf ~= -1 and vim.api.nvim_buf_is_valid(existing_buf) then
    buf = existing_buf
  else
    buf = vim.api.nvim_create_buf(false, true)
    pcall(vim.api.nvim_buf_set_name, buf, 'pi-chat://chat')
    vim.api.nvim_set_option_value('filetype', 'pichat', { buf = buf })
    vim.api.nvim_set_option_value('buftype', 'nofile', { buf = buf })
    vim.api.nvim_set_option_value('bufhidden', 'hide', { buf = buf })
    vim.api.nvim_set_option_value('swapfile', false, { buf = buf })
    vim.api.nvim_set_option_value('modifiable', true, { buf = buf })
  end

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
  vim.api.nvim_buf_clear_namespace(buf, diff_ns, 0, -1)
  active_renderers = {}
end

function M.append_seperator(text)
  M.append_newline()
  if text and text ~= '' then
    local part = '─ ' .. text .. ' '
    M.append_lines { part .. string.rep('─', line_width - #part) }
  else
    M.append_lines { string.rep('─', line_width) }
  end
end

-- Render a message event from pi
function M.render_message(msg)
  local msg_type = msg.type

  if msg_type == 'agent_start' then
  elseif msg_type == 'agent_end' then
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
    M.append_newline()
  elseif msg_type == 'tool_execution_start' then
    M.append_tool_start(msg.toolName, msg.args)
  elseif msg_type == 'tool_execution_update' then
  elseif msg_type == 'tool_execution_end' then
    M.append_text(vim.inspect(msg))
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
  elseif event_type == 'thinking_start' then
    M.append_seperator 'Thinking...'
    M.append_newline()
  elseif event_type == 'thinking_delta' then
    M.append_text(event.delta)
  elseif event_type == 'thinking_end' then
    M.append_newline()
  elseif event_type == 'toolcall_start' then
  elseif event_type == 'toolcall_delta' then
  elseif event_type == 'toolcall_end' then
    M.append_toolcall_end(event.toolCall)
  elseif event_type == 'text_start' then
    M.append_seperator 'Pi'
    M.append_newline()
  elseif event_type == 'text_end' then
    -- no-op, handled in delta
  else
    vim.notify('[pi-agent]: unknown event type: ' .. event_type .. ' ' .. vim.inspect(event), vim.log.levels.WARN)
  end
end

function M.append_content_with_header(header, text)
  local content = vim.split(text, '\n', { plain = true })
  M.append_seperator(header)
  M.append_lines(content)
end

function M.add_user_message(text)
  M.append_content_with_header('User', text)
end

function M.append_text(text)
  if not text or text == '' then
    return
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

function M.append_tool_start(toolName, args)
  -- If a call renderer is defined, it will handle display; skip raw tool start
  local renderer = M.tool_renderers[toolName]
  if renderer and renderer.call then
    return
  end

  M.append_newline()
  M.append_seperator('Tool: ' .. toolName)
  if args then
    M.append_lines { vim.json.encode(args) }
  end
end

function M.append_tool_end(toolCallId, result, isError)
  -- if M.tool_renderers.renderer[]  then
  --   entry.renderer.result {
  --     chat = M,
  --     toolCallId = toolCallId,
  --     result = result,
  --     isError = isError,
  --     toolCall = entry.toolCall,
  --   }
  --   return
  -- end
  --
  local content = {}

  if result and result.content then
    for _, item in ipairs(result.content) do
      if item.type == 'text' then
        for _, line in ipairs(vim.split(item.text, '\n', { plain = true })) do
          table.insert(content, line)
        end
      end
    end
  end

  M.append_lines(content)
  M.append_newline()
end

function M.append_error(err)
  M.append_content_with_header('Error', err)
end

function M.append_info(info)
  M.append_lines { '', '-- ' .. info .. ' --', '' }
end

local function read_file_content(path)
  local file = io.open(path, 'r')
  if not file then
    return nil
  end
  local content = file:read '*a'
  file:close()
  return content
end

local function apply_edits(content, edits)
  local replacements = {}
  for _, edit in ipairs(edits) do
    local oldText = edit.oldText
    local newText = edit.newText
    if type(oldText) == 'string' and type(newText) == 'string' then
      local idx = string.find(content, oldText, 1, true)
      if idx then
        table.insert(replacements, {
          idx = idx,
          len = #oldText,
          text = newText,
        })
      end
    end
  end

  -- Apply in reverse order to keep indices stable
  table.sort(replacements, function(a, b)
    return a.idx > b.idx
  end)

  for _, rep in ipairs(replacements) do
    content = string.sub(content, 1, rep.idx - 1) .. rep.text .. string.sub(content, rep.idx + rep.len)
  end

  return content
end

local function reconstruct_original(content, edits)
  local replacements = {}
  for i = #edits, 1, -1 do
    local edit = edits[i]
    local oldText = edit.oldText
    local newText = edit.newText
    if type(oldText) == 'string' and type(newText) == 'string' then
      local idx = string.find(content, newText, 1, true)
      if idx then
        table.insert(replacements, {
          idx = idx,
          len = #newText,
          text = oldText,
        })
      end
    end
  end

  table.sort(replacements, function(a, b)
    return a.idx > b.idx
  end)

  for _, rep in ipairs(replacements) do
    content = string.sub(content, 1, rep.idx - 1) .. rep.text .. string.sub(content, rep.idx + rep.len)
  end

  return content
end

local function generate_edit_diff(path, edits)
  local full_path = vim.fn.fnamemodify(path, ':p')
  local current_content = read_file_content(full_path) or ''

  local old_content, new_content
  local first_edit = edits[1]
  local first_old = first_edit and first_edit.oldText

  if first_old and string.find(current_content, first_old, 1, true) then
    -- File is in pre-edit state
    old_content = current_content
    new_content = apply_edits(current_content, edits)
  elseif first_edit and first_edit.newText and string.find(current_content, first_edit.newText, 1, true) then
    -- File already has edits applied; reconstruct original
    new_content = current_content
    old_content = reconstruct_original(current_content, edits)
  else
    -- Can't determine file state
    return nil
  end

  local diff = vim.diff(old_content, new_content, {
    result_type = 'unified',
    ctxlen = 3,
  })

  -- vim.diff returns empty string when there are no differences
  if diff == '' then
    return nil
  end

  return diff
end

local function render_diff_lines(lines)
  local start_line = vim.api.nvim_buf_line_count(buf)
  M.append_lines(lines)

  for i, line in ipairs(lines) do
    local line_idx = start_line + i - 1
    local prefix = string.sub(line, 1, 1)
    if prefix == '+' then
      vim.api.nvim_buf_set_extmark(buf, diff_ns, line_idx, 0, {
        line_hl_group = 'DiffAdd',
      })
    elseif prefix == '-' then
      vim.api.nvim_buf_set_extmark(buf, diff_ns, line_idx, 0, {
        line_hl_group = 'DiffDelete',
      })
    elseif prefix == '@' then
      vim.api.nvim_buf_set_extmark(buf, diff_ns, line_idx, 0, {
        line_hl_group = 'DiffChange',
      })
    end
  end
end

M.tool_renderers['edit'] = {
  result = function(ctx)
    local args = ctx.toolCall.arguments
    local diff = generate_edit_diff(args.path, args.edits)

    ctx.chat.append_seperator('Edit: ' .. args.path)
    if diff then
      local lines = vim.split(diff, '\n', { plain = true })
      -- Remove trailing empty line from split
      if lines[#lines] == '' then
        table.remove(lines)
      end
      render_diff_lines(lines)
    else
      ctx.chat.append_lines { '  (could not generate diff)' }
      local content = vim.split(vim.json.encode(args), '\n', { plain = true })
      ctx.chat.append_lines(content)
    end
    ctx.chat.append_newline()
  end,
}

-- Extract text string from message content (handles both string and table formats)
local function extract_text(content)
  if type(content) == 'string' then
    return content
  elseif type(content) == 'table' then
    -- Content is an array of content blocks
    local texts = {}
    for _, block in ipairs(content) do
      if block.type == 'text' and block.text then
        table.insert(texts, block.text)
      end
    end
    return table.concat(texts, '\n')
  end
  return ''
end

-- Render historical messages from a session
function M.render_history(messages)
  if not messages or #messages == 0 then
    return
  end

  for _, msg in ipairs(messages) do
    if msg.role == 'user' then
      M.add_user_message(extract_text(msg.content))
    elseif msg.role == 'assistant' then
      -- Render assistant message - process content blocks in document order
      if type(msg.content) == 'table' then
        local in_text_section = false

        for _, part in ipairs(msg.content) do
          if part.type == 'text' then
            -- Open a Pi section on first text block (or if not already open)
            if not in_text_section then
              M.append_seperator 'Pi'
              M.append_newline()
              in_text_section = true
            end
            if part.text and part.text ~= '' then
              M.append_text(part.text)
            end
          elseif part.type == 'thinking' then
            -- Close any open text section before thinking
            if in_text_section then
              M.append_newline()
              in_text_section = false
            end
            M.append_seperator 'Thinking...'
            M.append_newline()
            if part.thinking and part.thinking ~= '' then
              M.append_text(part.thinking)
            end
            M.append_newline()
          elseif part.type == 'toolCall' then
            -- Close any open text section before tool call
            if in_text_section then
              M.append_newline()
              in_text_section = false
            end
            M.append_toolcall_end(part)
          end
          -- Skip image blocks
        end

        -- Close trailing text section
        if in_text_section then
          M.append_newline()
        end
      elseif type(msg.content) == 'string' then
        -- Plain text response
        M.append_seperator 'Pi'
        M.append_newline()
        M.append_text(msg.content)
        M.append_newline()
      end
    elseif msg.role == 'toolResult' then
      -- Tool result messages returned by get_messages
      M.append_tool_end(msg.toolCallId, { content = msg.content }, msg.isError)
    end
  end

  -- Scroll to bottom
  M.scroll_to_bottom()
end

return M
