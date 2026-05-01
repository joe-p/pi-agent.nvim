-- pi.nvim session state management

local M = {}

-- Lazy load commands to avoid circular dependencies
local function get_commands()
  return require 'pi-agent.commands'
end

-- Session state
local state = {
  isStreaming = false,
  isCompacting = false,
  currentActivity = 'waiting',
  steeringMode = 'one-at-a-time',
  followUpMode = 'one-at-a-time',
  sessionFile = nil,
  sessionId = nil,
  sessionName = nil,
  messageCount = 0,
  model = nil,
}

-- Message history (for reference)
local messages = {}

-- Extension statuses from setStatus RPC
local extension_statuses = {}

-- Cumulative token usage and cost
local usage = {
  input = 0,
  output = 0,
  cacheRead = 0,
  cacheWrite = 0,
  cost = 0,
}

-- Handle incoming messages
function M.handle_message(msg)
  local msg_type = msg.type

  -- Update state from state responses
  if msg_type == 'response' and msg.command == 'get_state' then
    if msg.success and msg.data then
      state.isStreaming = msg.data.isStreaming
      state.isCompacting = msg.data.isCompacting
      state.steeringMode = msg.data.steeringMode
      state.followUpMode = msg.data.followUpMode
      state.sessionFile = msg.data.sessionFile
      state.sessionId = msg.data.sessionId
      state.sessionName = msg.data.sessionName
      state.messageCount = msg.data.messageCount
      state.model = msg.data.model
    end
    return
  end

  -- Response for get_commands - handled by commands module
  if msg_type == 'response' and msg.command == 'get_commands' then
    return
  end

  -- Track streaming state from events
  if msg_type == 'agent_start' then
    state.isStreaming = true
    state.currentActivity = 'responding'
  elseif msg_type == 'agent_end' then
    state.isStreaming = false
    state.currentActivity = 'waiting'
    -- Update message count
    if msg.messages then
      state.messageCount = #msg.messages
    end
  elseif msg_type == 'compaction_start' then
    state.isCompacting = true
  elseif msg_type == 'compaction_end' then
    state.isCompacting = false
  end

  -- Store in history for reference
  table.insert(messages, msg)

  -- Keep history manageable (last 1000 messages)
  if #messages > 1000 then
    table.remove(messages, 1)
  end
end

-- Extension status tracking
function M.set_extension_status(key, text)
  if text == nil or text == '' then
    extension_statuses[key] = nil
  else
    extension_statuses[key] = text
  end
end

function M.get_extension_statuses()
  local result = {}
  for _, text in pairs(extension_statuses) do
    table.insert(result, text)
  end
  return result
end

-- Get current state
function M.set_current_activity(activity)
  state.currentActivity = activity
end

function M.get_current_activity()
  return state.currentActivity
end

function M.get_state()
  return vim.deepcopy(state)
end

-- Token usage tracking
function M.add_usage(u)
  if not u then
    return
  end
  usage.input = usage.input + (u.input or 0)
  usage.output = usage.output + (u.output or 0)
  usage.cacheRead = usage.cacheRead + (u.cacheRead or 0)
  usage.cacheWrite = usage.cacheWrite + (u.cacheWrite or 0)
  if u.cost then
    usage.cost = usage.cost + (u.cost.total or 0)
  end
end

function M.get_usage()
  return vim.deepcopy(usage)
end

function M.clear_usage()
  usage.input = 0
  usage.output = 0
  usage.cacheRead = 0
  usage.cacheWrite = 0
  usage.cost = 0
end

-- Check if agent is busy
function M.is_busy()
  return state.isStreaming or state.isCompacting
end

-- Get session info
function M.get_session_info()
  return {
    file = state.sessionFile,
    id = state.sessionId,
    name = state.sessionName,
  }
end

-- Get current model
function M.get_model()
  return state.model
end

-- Clear message history (on new session)
function M.clear_history()
  messages = {}
  get_commands().clear()
  M.clear_usage()
end

-- Fetch commands from pi (requires rpc module)
function M.fetch_commands(rpc)
  get_commands().fetch(rpc)
end

-- Get messages (for debugging or /tree-like functionality)
function M.get_messages()
  return vim.deepcopy(messages)
end

return M
