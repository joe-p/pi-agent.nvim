-- pi.nvim RPC client
-- Handles JSONL protocol over stdin/stdout using Neovim job API

local M = {}

local job_id = nil
local request_id = 0
local pending_requests = {}
local stdout_buffer = ''

local callbacks = {}

-- Generate unique request ID
local function next_id()
  request_id = request_id + 1
  return 'pi-' .. tostring(request_id)
end

-- Send a command to pi
function M.send(cmd, callback)
  if not job_id then
    vim.notify('pi is not running', vim.log.levels.ERROR)
    return nil
  end
  
  local id = next_id()
  cmd.id = id
  
  if callback then
    pending_requests[id] = callback
  end
  
  local json = vim.json.encode(cmd)
  vim.fn.chansend(job_id, json .. '\n')
  
  return id
end

-- Process a line of output
local function process_line(line)
  -- Strip trailing \r if present (for \r\n compatibility)
  if line:sub(-1) == '\r' then
    line = line:sub(1, -2)
  end
  
  -- Skip empty lines
  if line == '' then
    return
  end
  
  -- Parse JSON
  local ok, msg = pcall(vim.json.decode, line)
  if ok then
    M.handle_message(msg)
  else
    vim.notify('Failed to parse JSON: ' .. line:sub(1, 100), vim.log.levels.ERROR)
  end
end

-- Handle stdout data with JSONL framing
local function on_stdout(_, data, _)
  if not data then
    return
  end
  
  -- Debug: show raw data received
  vim.notify('[pi] raw stdout: ' .. vim.fn.json_encode(data), vim.log.levels.DEBUG, { title = 'pi.nvim' })
  
  for _, chunk in ipairs(data) do
    if chunk ~= '' then
      stdout_buffer = stdout_buffer .. chunk
      
      -- Process complete lines (\n is the only delimiter per protocol)
      while true do
        local nl_pos = stdout_buffer:find('\n')
        if not nl_pos then
          break
        end
        
        local line = stdout_buffer:sub(1, nl_pos - 1)
        stdout_buffer = stdout_buffer:sub(nl_pos + 1)
        
        vim.notify('[pi] line: ' .. line:sub(1, 100), vim.log.levels.DEBUG, { title = 'pi.nvim' })
        
        process_line(line)
      end
    end
  end
end

-- Handle stderr
local function on_stderr(_, data, _)
  if not data then
    return
  end
  
  -- Debug: show all stderr
  vim.notify('[pi] raw stderr: ' .. vim.fn.json_encode(data), vim.log.levels.DEBUG, { title = 'pi.nvim' })
  
  for _, chunk in ipairs(data) do
    if chunk ~= '' then
      vim.notify('pi stderr: ' .. chunk, vim.log.levels.WARN)
      if callbacks.on_error then
        callbacks.on_error(chunk)
      end
    end
  end
end

-- Handle job exit
local function on_exit(_, exit_code, _)
  vim.schedule(function()
    if exit_code ~= 0 then
      vim.notify('pi exited with code ' .. exit_code, vim.log.levels.ERROR)
    end
    M.cleanup()
    if callbacks.on_exit then
      callbacks.on_exit(exit_code)
    end
  end)
end

-- Start the pi process
function M.start(cmd, opts)
  callbacks = opts or {}
  stdout_buffer = ''
  
  local job_opts = {
    rpc = false,
    pty = true, -- Use pty to get line-buffered output (fixes buffering issues)
    stdout_buffered = false,
    stderr_buffered = false,
    on_stdout = on_stdout,
    on_stderr = on_stderr,
    on_exit = on_exit,
  }
  
  -- Convert command array to string for jobstart
  -- jobstart expects a list: {command, arg1, arg2, ...}
  job_id = vim.fn.jobstart(cmd, job_opts)
  
  if job_id == -1 then
    vim.notify('Failed to spawn pi process: command not found', vim.log.levels.ERROR)
    return false
  elseif job_id == 0 then
    vim.notify('Failed to spawn pi process: invalid arguments', vim.log.levels.ERROR)
    return false
  end
  
  vim.notify('pi started (job ' .. job_id .. ')', vim.log.levels.INFO)
  return true
end

-- Handle incoming messages from pi
function M.handle_message(msg)
  -- Debug: show event type
  if msg.type then
    vim.notify('[pi] Event: ' .. msg.type .. (msg.command and (' (' .. msg.command .. ')') or ''), vim.log.levels.DEBUG, { title = 'pi.nvim' })
  end
  
  -- Handle responses (correlated by id)
  if msg.id and pending_requests[msg.id] then
    local callback = pending_requests[msg.id]
    pending_requests[msg.id] = nil
    callback(msg)
    return
  end
  
  -- Forward to message handler
  if callbacks.on_message then
    callbacks.on_message(msg)
  end
end

-- Stop the pi process
function M.stop()
  if not job_id then
    return
  end
  
  -- Send abort first
  M.send({ type = 'abort' })
  
  -- Give it a moment to clean up
  vim.defer_fn(function()
    if job_id then
      vim.fn.jobstop(job_id)
    end
  end, 100)
end

-- Cleanup internal state
function M.cleanup()
  job_id = nil
  stdout_buffer = ''
  -- Keep pending_requests in case of reconnect
end

-- Check if running
function M.is_running()
  if not job_id then
    return false
  end
  -- Check if job is still active
  local status = vim.fn.jobwait({ job_id }, 0)
  return status[1] == -1
end

-- Get request that matches a predicate (for extension UI)
function M.get_pending_request(id)
  return pending_requests[id]
end

return M