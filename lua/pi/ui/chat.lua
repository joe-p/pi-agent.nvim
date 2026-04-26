-- pi.nvim chat buffer (output)

local M = {}

local buf = nil
local opts = {}
local session = require 'pi.session'

local line_width = 63
local diff_ns = vim.api.nvim_create_namespace 'pi_chat_diff'
local thinking_ns = vim.api.nvim_create_namespace 'pi_chat_thinking'
local sep_ns = vim.api.nvim_create_namespace 'pi_chat_sep'

-- Extract text lines from a result's content blocks
local function extract_result_lines(result)
  local lines = {}
  if result and result.content then
    for _, item in ipairs(result.content) do
      if item.type == 'text' and item.text then
        for _, line in ipairs(vim.split(item.text, '\n', { plain = true })) do
          table.insert(lines, line)
        end
      end
    end
  end
  return lines
end

function M.setup(config)
  opts = config
  vim.api.nvim_set_hl(0, 'PiChatThinking', { link = 'Comment' })
  vim.api.nvim_set_hl(0, 'PiChatSeparator', { italic = true })
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
    vim.api.nvim_set_option_value('readonly', false, { buf = buf })
  end

  local close_key = opts.keymaps and opts.keymaps.close or 'q'
  vim.api.nvim_buf_set_keymap(buf, 'n', close_key, '<cmd>PiToggle<CR>', { noremap = true, silent = true })

  local cancel_key = opts.keymaps and opts.keymaps.cancel or '<C-x>'
  vim.api.nvim_buf_set_keymap(buf, 'n', cancel_key, '', {
    noremap = true,
    silent = true,
    callback = function()
      require('pi.rpc').send { type = 'abort' }
    end,
  })

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
  vim.api.nvim_set_option_value('statusline', '%!v:lua._pi_chat_statusline()', { win = win })
end

-- Strip ANSI escape sequences so they don't render literally in statusline
local function strip_ansi(text)
  return (text:gsub('\27%[[0-9;]*%a', ''))
end

-- Global statusline function for pichat windows
_G._pi_chat_statusline = function()
  local session = require 'pi.session'
  local state = session.get_state()
  local usage = session.get_usage()
  local parts = {}

  -- Session state indicators
  if state.isStreaming then
    local activity = state.currentActivity or 'responding'
    local emoji_map = {
      waiting = '💤',
      thinking = '🧠',
      tool_calling = '🛠️',
      responding = '💬',
    }
    table.insert(parts, emoji_map[activity] or '💬')
  end
  if state.isCompacting then
    table.insert(parts, '🗜️')
  end
  if not state.isStreaming and not state.isCompacting then
    table.insert(parts, '💤')
  end

  -- Extension statuses from setStatus RPC
  local statuses = session.get_extension_statuses()
  for _, text in ipairs(statuses) do
    table.insert(parts, strip_ansi(text))
  end

  -- Current model
  if state.model then
    local model_name = state.model.name or state.model.id or 'unknown'
    table.insert(parts, model_name)
  end

  -- Usage stats
  if usage and (usage.input > 0 or usage.output > 0 or usage.cost > 0) then
    local function fmt_num(n)
      if n >= 1000 then
        return string.format('%.1fk', n / 1000)
      else
        return tostring(n)
      end
    end
    local usage_parts = {}
    if usage.input > 0 then
      table.insert(usage_parts, '↑' .. fmt_num(usage.input))
    end
    if usage.output > 0 then
      table.insert(usage_parts, '↓' .. fmt_num(usage.output))
    end
    if usage.cacheRead > 0 then
      table.insert(usage_parts, 'cr:' .. fmt_num(usage.cacheRead))
    end
    if usage.cacheWrite > 0 then
      table.insert(usage_parts, 'cw:' .. fmt_num(usage.cacheWrite))
    end
    local cost_str
    if usage.cost >= 0.01 then
      cost_str = string.format('$%.2f', usage.cost)
    else
      cost_str = string.format('$%.4f', usage.cost)
    end
    table.insert(usage_parts, cost_str)
    table.insert(parts, table.concat(usage_parts, ' '))
  end

  -- Build statusline
  local left = table.concat(parts, ' │ ')
  return '%#StatusLine#' .. left .. '%=%#StatusLine#%l:%c'
end

-- Refresh statusline in all pichat windows
function M.refresh_statusline()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) then
      local bufnr = vim.api.nvim_win_get_buf(win)
      local ft = vim.api.nvim_get_option_value('filetype', { buf = bufnr })
      if ft == 'pichat' then
        vim.api.nvim_set_option_value('statusline', '%!v:lua._pi_chat_statusline()', { win = win })
      end
    end
  end
  vim.cmd 'redrawstatus!'
end

function M.clear()
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
  vim.api.nvim_buf_clear_namespace(buf, diff_ns, 0, -1)
  vim.api.nvim_buf_clear_namespace(buf, thinking_ns, 0, -1)
  vim.api.nvim_buf_clear_namespace(buf, sep_ns, 0, -1)
end

function M.append_seperator(text)
  M.append_newline()
  local timestamp = os.date '[%H:%M::%S] '
  if text and text ~= '' then
    local prefix = '── '
    local suffix = ' '
    local part = prefix .. timestamp .. text .. suffix
    local line = part .. string.rep('─', line_width - #part)
    M.append_lines { line }
    if buf and vim.api.nvim_buf_is_valid(buf) then
      local line_count = vim.api.nvim_buf_line_count(buf)
      local line_idx = line_count - 1
      local text_start = #prefix
      vim.api.nvim_buf_set_extmark(buf, sep_ns, line_idx, text_start, {
        end_col = text_start + #timestamp + #text,
        hl_group = 'PiChatSeparator',
        hl_mode = 'combine',
      })
    end
  else
    local line = timestamp .. string.rep('─', line_width - #timestamp)
    M.append_lines { line }
  end
  M.append_newline()
end

-- Type definitions for RPC events
-- See: https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/docs/rpc.md

---@class ToolCall
---@field id string
---@field name string
---@field arguments table

---@class ContentBlock
---@field type "text"|"thinking"|"toolCall"
---@field text? string
---@field thinking? string
---@field id? string
---@field name? string
---@field arguments? table

---@class AgentMessage
---@field role "user"|"assistant"|"toolResult"
---@field content string|ContentBlock[]
---@field timestamp number
---@field attachments? table[]
---@field toolCallId? string
---@field toolName? string
---@field isError? boolean
---@field errorMessage? string

---@class UsageCost
---@field input number
---@field output number
---@field cacheRead number
---@field cacheWrite number
---@field total number

---@class Usage
---@field input number
---@field output number
---@field cacheRead number
---@field cacheWrite number
---@field cost UsageCost

---@class AssistantAgentMessage : AgentMessage
---@field role "assistant"
---@field api string
---@field provider string
---@field model string
---@field usage Usage
---@field stopReason "stop"|"length"|"toolUse"|"error"|"aborted"

---@class ToolResult
---@field content table[]
---@field details? table

---@class CompactionResult
---@field summary string
---@field firstKeptEntryId string
---@field tokensBefore number
---@field details table

---@class MessageHandlerContext

---@alias AgentStartEvent { type: "agent_start" }
---@alias AgentEndEvent { type: "agent_end", messages: AgentMessage[] }
---@alias TurnStartEvent { type: "turn_start" }
---@alias TurnEndEvent { type: "turn_end", message: AgentMessage, toolResults: ToolResult[] }
---@alias MessageStartEvent { type: "message_start", message: AgentMessage }
---@alias MessageEndEvent { type: "message_end", message: AgentMessage }
---@alias MessageUpdateEvent { type: "message_update", message: AgentMessage, assistantMessageEvent: AssistantMessageEvent }
---@alias ToolExecutionStartEvent { type: "tool_execution_start", toolCallId: string, toolName: string, args: table }
---@alias ToolExecutionUpdateEvent { type: "tool_execution_update", toolCallId: string, toolName: string, args: table, partialResult: ToolResult }
---@alias ToolExecutionEndEvent { type: "tool_execution_end", toolCallId: string, toolName: string, result: ToolResult, isError: boolean }
---@alias ErrorEvent { type: "error", error: string }
---@alias ExtensionErrorEvent { type: "extension_error", extensionPath: string, event: string, error: string }
---@alias CompactionStartEvent { type: "compaction_start", reason: "manual"|"threshold"|"overflow" }
---@alias CompactionEndEvent { type: "compaction_end", reason: string, result: CompactionResult?, aborted: boolean, willRetry: boolean }
---@alias AutoRetryStartEvent { type: "auto_retry_start", attempt: number, maxAttempts: number, delayMs: number, errorMessage: string }
---@alias AutoRetryEndEvent { type: "auto_retry_end", success: boolean, attempt: number, finalError?: string }
---@alias QueueUpdateEvent { type: "queue_update", steering: string[], followUp: string[] }
---@alias ExtensionUIRequestEvent { type: "extension_ui_request", id: string, method: string, [string]: any }

---@alias MessageEvent AgentStartEvent|AgentEndEvent|TurnStartEvent|TurnEndEvent|MessageStartEvent|MessageEndEvent|MessageUpdateEvent|ToolExecutionStartEvent|ToolExecutionUpdateEvent|ToolExecutionEndEvent|ErrorEvent|ExtensionErrorEvent|CompactionStartEvent|CompactionEndEvent|AutoRetryStartEvent|AutoRetryEndEvent|QueueUpdateEvent|ExtensionUIRequestEvent

---@class ToolRenderer
---@field execution_start? fun(chat, start: ToolExecutionStartEvent): nil
---@field execution_update? fun(chat, start: ToolExecutionStartEvent, update: ToolExecutionUpdateEvent): nil
---@field execution_end? fun(chat, start: ToolExecutionStartEvent, end: ToolExecutionEndEvent): nil

-- Map of tool names to renderer descriptor tables.
---@type { [string]: ToolRenderer }
local tool_renderers = {}

---@type {[string]: ToolExecutionStartEvent}
local tool_executions = {}

---@type AssistantAgentMessage | nil
M.current_assistant = nil

--- Message type handlers: msg.type -> function(msg)
-- See: https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/docs/rpc.md#event-types
---@type table[string, fun(msg: MessageEvent)>
local message_handlers = {
  -- Agent lifecycle
  ---@param msg AgentStartEvent
  agent_start = function(msg)
    -- Emitted when the agent begins processing a prompt
    M.refresh_statusline()
  end,
  ---@param msg AgentEndEvent
  agent_end = function(msg)
    -- Emitted when the agent completes. Contains all messages generated during this run.
    M.current_assistant = nil
    M.refresh_statusline()
    if msg.messages then
      for _, m in ipairs(msg.messages) do
        if m.errorMessage then
          if m.errorMessage == 'Request was aborted' then
            M.append_info(m.errorMessage)
          else
            vim.notify('pi-agent ERROR: ' .. m.errorMessage, vim.log.levels.ERROR)
            M.append_error(m.errorMessage)
          end
        end
      end
    end
  end,

  -- Turn lifecycle (a turn = one assistant response + resulting tool calls/results)
  ---@param msg TurnStartEvent
  turn_start = function(msg)
    -- New turn begins
  end,
  ---@param msg TurnEndEvent
  turn_end = function(msg)
    -- Turn completes. Contains: message (assistant), toolResults (array)
  end,

  -- Message lifecycle
  ---@param msg MessageStartEvent
  message_start = function(msg)
    -- Message begins. msg.message contains the AgentMessage

    local agentMsg = msg.message ---@cast agentMsg AssistantAgentMessage
    M.current_assistant = agentMsg
    session.set_current_activity 'responding'
    M.refresh_statusline()
  end,
  ---@param msg MessageUpdateEvent
  message_update = function(msg)
    -- Streaming update (text/thinking/toolcall deltas)
    M.handle_message_update(msg)
  end,
  ---@param msg MessageEndEvent
  message_end = function(msg)
    -- Message completes. msg.message contains the completed AgentMessage
    local message = msg.message or M.current_assistant
    if message and message.role == 'assistant' and message.usage then
      session.add_usage(message.usage)
    end
    M.current_assistant = nil
  end,

  -- Tool execution lifecycle
  ---@param msg ToolExecutionStartEvent
  tool_execution_start = function(msg)
    tool_executions[msg.toolCallId] = msg
    session.set_current_activity 'tool_calling'
    M.refresh_statusline()
    local renderer = tool_renderers[msg.toolName]
    if renderer and renderer.execution_start then
      renderer.execution_start(M, msg)
      return
    end

    M.append_seperator('Executing Tool: ' .. msg.toolName)
    if msg.args then
      M.append_lines { vim.json.encode(msg.args) }
    end
  end,
  ---@param msg ToolExecutionUpdateEvent
  tool_execution_update = function(msg)
    -- Tool execution progress (streaming output). Contains: partialResult
  end,
  ---@param msg ToolExecutionEndEvent
  tool_execution_end = function(msg)
    -- Tool completes. Contains: toolCallId, toolName, result, isError

    local tool_start = tool_executions[msg.toolCallId]
    tool_executions[msg.toolCallId] = nil

    local renderer = tool_renderers[msg.toolName]

    if renderer and renderer.execution_end then
      renderer.execution_end(M, tool_start, msg)
      return
    end

    M.append_lines(extract_result_lines(msg.result))
  end,

  -- Errors
  ---@param msg ErrorEvent
  error = function(msg)
    -- General error event
    M.append_error(msg.error or 'Unknown error')
  end,
  ---@param msg ExtensionErrorEvent
  extension_error = function(msg)
    -- Extension threw an error. Contains: extensionPath, event, error
    M.append_error(msg.error or 'Unknown error')
  end,

  -- Compaction
  ---@param msg CompactionStartEvent
  compaction_start = function(msg)
    -- Compaction begins. msg.reason: "manual", "threshold", or "overflow"
    M.append_info 'Compacting conversation...'
    M.refresh_statusline()
  end,
  ---@param msg CompactionEndEvent
  compaction_end = function(msg)
    -- Compaction completes. Contains: reason, result (summary, etc.), aborted, willRetry
    M.append_info 'Compaction complete'
    M.refresh_statusline()
  end,

  -- Auto-retry
  ---@param msg AutoRetryStartEvent
  auto_retry_start = function(msg)
    -- Auto-retry begins after transient error. Contains: attempt, maxAttempts, delayMs, errorMessage
    M.append_info(string.format('Retrying... (attempt %d/%d)', msg.attempt, msg.maxAttempts))
  end,
  ---@param msg AutoRetryEndEvent
  auto_retry_end = function(msg)
    -- Auto-retry completes. Contains: success, attempt, finalError (on failure)
  end,

  -- Queue
  ---@param msg QueueUpdateEvent
  queue_update = function(msg)
    -- Pending steering/follow-up queue changed. Contains: steering (array), followUp (array)
  end,

  -- Extension UI
  ---@param msg ExtensionUIRequestEvent
  extension_ui_request = function(msg)
    -- Extension UI request (select, confirm, input, editor, notify, etc.)
    require('pi.extension_ui').handle_request(msg)
  end,
}

--- Type definitions for assistant message streaming events
---@alias AssistantMessageEventStart { type: "start", contentIndex?: number, partial?: table }
---@alias AssistantMessageEventDone { type: "done", contentIndex?: number, reason: "stop"|"length"|"toolUse", partial?: table }
---@alias AssistantMessageEventError { type: "error", contentIndex?: number, reason: "aborted"|"error", partial?: table }
---@alias AssistantMessageEventTextStart { type: "text_start", contentIndex: number, partial: table }
---@alias AssistantMessageEventTextDelta { type: "text_delta", contentIndex: number, delta: string, partial: table }
---@alias AssistantMessageEventTextEnd { type: "text_end", contentIndex: number, content: string, partial: table }
---@alias AssistantMessageEventThinkingStart { type: "thinking_start", contentIndex: number, partial: table }
---@alias AssistantMessageEventThinkingDelta { type: "thinking_delta", contentIndex: number, delta: string, partial: table }
---@alias AssistantMessageEventThinkingEnd { type: "thinking_end", contentIndex: number, content: string, partial: table }
---@alias AssistantMessageEventToolCallStart { type: "toolcall_start", contentIndex: number, partial: table }
---@alias AssistantMessageEventToolCallDelta { type: "toolcall_delta", contentIndex: number, delta: string, partial: table }
---@alias AssistantMessageEventToolCallEnd { type: "toolcall_end", contentIndex: number, toolCall: ToolCall, partial: table }

---@alias AssistantMessageEvent AssistantMessageEventStart|AssistantMessageEventDone|AssistantMessageEventError|AssistantMessageEventTextStart|AssistantMessageEventTextDelta|AssistantMessageEventTextEnd|AssistantMessageEventThinkingStart|AssistantMessageEventThinkingDelta|AssistantMessageEventThinkingEnd|AssistantMessageEventToolCallStart|AssistantMessageEventToolCallDelta|AssistantMessageEventToolCallEnd

---@class MessageUpdateEventData
---@field type "message_update"
---@field message AgentMessage
---@field assistantMessageEvent AssistantMessageEvent

---@class MessageUpdateEventGeneric
---@field type "message_update"
---@field message AgentMessage
---@field assistantMessageEvent AssistantMessageEvent

--- Narrowed MessageUpdateEvent types for specific handlers
---@alias MessageUpdateEventStart { type: "message_update", message: AgentMessage, assistantMessageEvent: AssistantMessageEventStart }
---@alias MessageUpdateEventDone { type: "message_update", message: AgentMessage, assistantMessageEvent: AssistantMessageEventDone }
---@alias MessageUpdateEventError { type: "message_update", message: AgentMessage, assistantMessageEvent: AssistantMessageEventError }
---@alias MessageUpdateEventTextStart { type: "message_update", message: AgentMessage, assistantMessageEvent: AssistantMessageEventTextStart }
---@alias MessageUpdateEventTextDelta { type: "message_update", message: AgentMessage, assistantMessageEvent: AssistantMessageEventTextDelta }
---@alias MessageUpdateEventTextEnd { type: "message_update", message: AgentMessage, assistantMessageEvent: AssistantMessageEventTextEnd }
---@alias MessageUpdateEventThinkingStart { type: "message_update", message: AgentMessage, assistantMessageEvent: AssistantMessageEventThinkingStart }
---@alias MessageUpdateEventThinkingDelta { type: "message_update", message: AgentMessage, assistantMessageEvent: AssistantMessageEventThinkingDelta }
---@alias MessageUpdateEventThinkingEnd { type: "message_update", message: AgentMessage, assistantMessageEvent: AssistantMessageEventThinkingEnd }
---@alias MessageUpdateEventToolCallStart { type: "message_update", message: AgentMessage, assistantMessageEvent: AssistantMessageEventToolCallStart }
---@alias MessageUpdateEventToolCallDelta { type: "message_update", message: AgentMessage, assistantMessageEvent: AssistantMessageEventToolCallDelta }
---@alias MessageUpdateEventToolCallEnd { type: "message_update", message: AgentMessage, assistantMessageEvent: AssistantMessageEventToolCallEnd }

--- Message update event handlers: event.type -> function(msg)
-- See: https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/docs/rpc.md#message_update-streaming
---@type { start: fun(msg: MessageUpdateEventStart), done: fun(msg: MessageUpdateEventDone), error: fun(msg: MessageUpdateEventError), text_start: fun(msg: MessageUpdateEventTextStart), text_delta: fun(msg: MessageUpdateEventTextDelta), text_end: fun(msg: MessageUpdateEventTextEnd), thinking_start: fun(msg: MessageUpdateEventThinkingStart), thinking_delta: fun(msg: MessageUpdateEventThinkingDelta), thinking_end: fun(msg: MessageUpdateEventThinkingEnd), toolcall_start: fun(msg: MessageUpdateEventToolCallStart), toolcall_delta: fun(msg: MessageUpdateEventToolCallDelta), toolcall_end: fun(msg: MessageUpdateEventToolCallEnd) }
local message_update_handlers = {
  -- Message lifecycle
  ---@param msg MessageUpdateEventStart
  start = function(msg)
    -- Message generation started
  end,
  ---@param msg MessageUpdateEventDone
  done = function(msg)
    -- Message complete. event.reason: "stop", "length", "toolUse"
  end,
  ---@param msg MessageUpdateEventError
  error = function(msg)
    -- Error occurred. event.reason: "aborted", "error"
  end,

  -- Text content
  ---@param msg MessageUpdateEventTextStart
  text_start = function(msg)
    -- Text content block started
    session.set_current_activity 'responding'
    M.refresh_statusline()
    local model = M.current_assistant and M.current_assistant.model or 'Assistant'
    M.append_seperator(model)
  end,
  ---@param msg MessageUpdateEventTextDelta
  text_delta = function(msg)
    -- Text content chunk
    M.append_text(msg.assistantMessageEvent.delta)
  end,
  ---@param msg MessageUpdateEventTextEnd
  text_end = function(msg)
    -- Text content block ended. event.content contains full text
  end,

  -- Thinking content
  ---@param msg MessageUpdateEventThinkingStart
  thinking_start = function(msg)
    -- Thinking block started
    session.set_current_activity 'thinking'
    M.refresh_statusline()
    local model = M.current_assistant and M.current_assistant.model or 'Assistant'
    M.append_seperator(model .. ' (thinking)')
    if buf and vim.api.nvim_buf_is_valid(buf) then
      M._thinking_start_line = vim.api.nvim_buf_line_count(buf) - 1
    end
  end,
  ---@param msg MessageUpdateEventThinkingDelta
  thinking_delta = function(msg)
    -- Thinking content chunk
    M.append_text(msg.assistantMessageEvent.delta)
    if buf and vim.api.nvim_buf_is_valid(buf) and M._thinking_start_line then
      local end_line = vim.api.nvim_buf_line_count(buf) - 1
      vim.api.nvim_buf_clear_namespace(buf, thinking_ns, M._thinking_start_line, end_line + 1)
      for line = M._thinking_start_line, end_line do
        local text = vim.api.nvim_buf_get_lines(buf, line, line + 1, false)[1] or ''
        if text ~= '' then
          vim.api.nvim_buf_add_highlight(buf, thinking_ns, 'PiChatThinking', line, 0, -1)
        end
      end
    end
  end,
  ---@param msg MessageUpdateEventThinkingEnd
  thinking_end = function(msg)
    -- Thinking block ended
    M._thinking_start_line = nil
  end,

  -- Tool calls
  ---@param msg MessageUpdateEventToolCallStart
  toolcall_start = function(msg)
    -- Tool call started. event.contentIndex, event.partial
    session.set_current_activity 'tool_calling'
    M.refresh_statusline()
  end,
  ---@param msg MessageUpdateEventToolCallDelta
  toolcall_delta = function(msg)
    -- Tool call arguments chunk. event.delta contains args JSON fragment
  end,
  ---@param msg MessageUpdateEventToolCallEnd
  toolcall_end = function(msg)
    -- Tool call ended. event.toolCall contains full ToolCall object
  end,
}

-- Render a message event from pi
---@param msg MessageEvent
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

  if buf == nil then
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

function M.append_error(err)
  M.append_content_with_header('Error', err)
end

function M.append_info(info)
  M.append_content_with_header('Info', info)
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

  local diff = vim.text.diff(old_content, new_content, {
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
  if buf == nil then
    return
  end

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

tool_renderers['edit'] = {
  execution_end = function(chat, start, t_end)
    local args = start.args
    local diff = generate_edit_diff(args.path, args.edits)

    chat.append_seperator('Edit: ' .. args.path)
    if diff and type(diff) == 'string' then
      local lines = vim.split(diff, '\n', { plain = true })
      -- Remove trailing empty line from split
      if lines[#lines] == '' then
        table.remove(lines)
      end
      render_diff_lines(lines)
    else
      chat.append_lines { '  (could not generate diff)' }
      local content = vim.split(vim.json.encode(args), '\n', { plain = true })
      chat.append_lines(content)
    end
  end,
}

tool_renderers['bash'] = {
  execution_start = function(chat, start)
    chat.append_lines { '```bash', '$ ' .. start.args.command, '```' }
  end,
  execution_end = function(chat, start, t_end)
    local lines = { '```bash' }
    vim.list_extend(lines, extract_result_lines(t_end.result))
    table.insert(lines, '```')
    chat.append_lines(lines)
  end,
}

tool_renderers['read'] = {
  execution_start = function(chat, start)
    M.append_seperator 'Read File'
    chat.append_lines { start.args.path }
  end,
  execution_end = function(chat, start, t_end)
    if t_end.isError then
      local lines = { 'Read error: ' }
      vim.list_extend(lines, extract_result_lines(t_end.result))
      chat.append_lines(lines)
    end
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
      M.render_message { type = 'message_start', message = msg }

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

      M.render_message { type = 'message_end', message = msg }
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
