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

-- Message type handlers: msg.type -> function(msg)
local message_handlers = {
  agent_start = function() end,
  agent_end = function(msg)
    if msg.messages then
      for _, m in ipairs(msg.messages) do
        if m.errorMessage then
          vim.notify('pi-agent ERROR: ' .. m.errorMessage, vim.log.levels.ERROR)
          M.append_error(m.errorMessage)
        end
      end
    end
  end,
  message_start = function() end,
  message_update = function(msg)
    M.handle_message_update(msg)
  end,
  message_end = function()
    M.append_newline()
  end,
  tool_execution_start = function(msg)
    M.append_tool_start(msg.toolName, msg.args)
  end,
  tool_execution_update = function() end,
  tool_execution_end = function(msg)
    M.append_text(vim.inspect(msg))
    M.append_tool_end(msg.toolCallId, msg.result, msg.isError)
  end,
  error = function(msg)
    M.append_error(msg.error or 'Unknown error')
  end,
  extension_error = function(msg)
    M.append_error(msg.error or 'Unknown error')
  end,
  compaction_start = function()
    M.append_info 'Compacting conversation...'
  end,
  compaction_end = function()
    M.append_info 'Compaction complete'
  end,
  queue_update = function() end,
  extension_ui_request = function(msg)
    require('pi.extension_ui').handle_request(msg)
  end,
}

-- Message update event handlers: event.type -> function(msg)
local message_update_handlers = {
  text_delta = function(msg)
    M.append_text(msg.assistantMessageEvent.delta)
  end,
  thinking_start = function()
    M.append_seperator 'Thinking...'
    M.append_newline()
  end,
  thinking_delta = function(msg)
    M.append_text(msg.assistantMessageEvent.delta)
  end,
  thinking_end = function()
    M.append_newline()
  end,
  toolcall_start = function() end,
  toolcall_delta = function() end,
  toolcall_end = function(msg)
    local toolCall = msg.assistantMessageEvent.toolCall
    local renderer = M.tool_renderers[toolCall.name]
    if renderer and renderer.call then
      return
    end
    M.append_newline()
    M.append_seperator('Tool: ' .. toolCall.name)
    if toolCall.arguments then
      M.append_lines { vim.json.encode(toolCall.arguments) }
    end
  end,
  text_start = function()
    M.append_seperator 'Pi'
    M.append_newline()
  end,
  text_end = function() end,
}

-- Render a message event from pi
function M.render_message(msg)
  local handler = message_handlers[msg.type]
  if handler then
    handler(msg)
  end
end

function M.handle_message_update(msg)
  local event = msg.assistantMessageEvent
  if not event then
    vim.notify('non-event: ' .. vim.inspect(msg))
    return
  end

  local handler = message_update_handlers[event.type]
  if handler then
    handler(msg)
  else
    vim.notify('[pi-agent]: unknown event type: ' .. event.type .. ' ' .. vim.inspect(event), vim.log.levels.WARN)
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
      M.render_message { type = 'message_start' }

      if type(msg.content) == 'table' then
        for _, part in ipairs(msg.content) do
          if part.type == 'text' then
            M.render_message {
              type = 'message_update',
              assistantMessageEvent = { type = 'text_start' },
            }
            if part.text and part.text ~= '' then
              M.render_message {
                type = 'message_update',
                assistantMessageEvent = { type = 'text_delta', delta = part.text },
              }
            end
            M.render_message {
              type = 'message_update',
              assistantMessageEvent = { type = 'text_end' },
            }
          elseif part.type == 'thinking' then
            M.render_message {
              type = 'message_update',
              assistantMessageEvent = { type = 'thinking_start' },
            }
            if part.thinking and part.thinking ~= '' then
              M.render_message {
                type = 'message_update',
                assistantMessageEvent = { type = 'thinking_delta', delta = part.thinking },
              }
            end
            M.render_message {
              type = 'message_update',
              assistantMessageEvent = { type = 'thinking_end' },
            }
          elseif part.type == 'toolCall' then
            M.render_message {
              type = 'message_update',
              assistantMessageEvent = {
                type = 'toolcall_end',
                toolCall = part,
              },
            }
          end
        end
      elseif type(msg.content) == 'string' then
        M.render_message {
          type = 'message_update',
          assistantMessageEvent = { type = 'text_start' },
        }
        if msg.content ~= '' then
          M.render_message {
            type = 'message_update',
            assistantMessageEvent = { type = 'text_delta', delta = msg.content },
          }
        end
        M.render_message {
          type = 'message_update',
          assistantMessageEvent = { type = 'text_end' },
        }
      end

      M.render_message { type = 'message_end' }
    elseif msg.role == 'toolResult' then
      M.render_message {
        type = 'tool_execution_end',
        toolCallId = msg.toolCallId,
        result = { content = msg.content },
        isError = msg.isError,
      }
    end
  end

  M.scroll_to_bottom()
end

return M
