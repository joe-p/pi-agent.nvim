-- pi.nvim RPC client
-- Uses vim.system for process management (Neovim 0.10+)

local M = {}

local job_id = nil
local request_id = 0
local pending_requests = {}

local callbacks = {}
local stdout_buffer = ''

-- Generate unique request ID
local function next_id()
  request_id = request_id + 1
  return 'pi-' .. tostring(request_id)
end

-- Parse and handle a line of JSONL
local function handle_line(line)
  if line == '' then
    return
  end

  -- Strip trailing \r if present (for \r\n compatibility)
  if line:sub(-1) == '\r' then
    line = line:sub(1, -2)
  end

  if line == '' then
    return
  end

  -- Try to parse as JSON
  local ok, msg = pcall(vim.json.decode, line)
  if not ok then
    -- Not valid JSON, treat as raw output
    if callbacks.on_stderr then
      callbacks.on_stderr(line)
    end
    return
  end

  -- Debug notification (uncomment for verbose logging)
  -- if msg.type then
  --   vim.notify('[pi] ' .. msg.type, vim.log.levels.DEBUG, { title = 'pi.nvim' })
  -- end

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

-- Feed data into line buffer, extracting complete lines
local function feed_stream(data)
  if not data or data == '' then
    return
  end

  stdout_buffer = stdout_buffer .. data

  -- Process complete lines (\n is the only delimiter per protocol)
  while true do
    local nl_pos = stdout_buffer:find('\n', 1, true)
    if not nl_pos then
      break
    end

    local line = stdout_buffer:sub(1, nl_pos - 1)
    stdout_buffer = stdout_buffer:sub(nl_pos + 1)

    handle_line(line)
  end
end

-- Send a command to pi
function M.send(cmd, callback)
  if not job_id then
    vim.notify('pi is not running', vim.log.levels.ERROR)
    return nil
  end

  -- Only generate new ID if one isn't already set (for responses)
  local id = cmd.id or next_id()
  cmd.id = id

  if callback then
    pending_requests[id] = callback
  end

  local json = vim.json.encode(cmd)

  -- Write to stdin
  local ok, err = pcall(function()
    job_id:write(json .. '\n')
  end)

  if not ok then
    vim.notify('Failed to send to pi: ' .. tostring(err), vim.log.levels.ERROR)
    return nil
  end

  return id
end

-- Start the pi process
function M.start(cmd, opts)
  callbacks = opts or {}
  stdout_buffer = ''

  local ok, process = pcall(
    vim.system,
    cmd,
    {
      text = true,
      stdin = true,
      stdout = vim.schedule_wrap(function(err, data)
        if err then
          if callbacks.on_error then
            callbacks.on_error(err)
          end
          return
        end
        if data then
          feed_stream(data)
        end
      end),
      stderr = vim.schedule_wrap(function(err, data)
        if err then
          if callbacks.on_error then
            callbacks.on_error(err)
          end
          return
        end
        if data and data ~= '' then
          vim.notify('pi stderr: ' .. data, vim.log.levels.WARN)
          if callbacks.on_stderr then
            callbacks.on_stderr(data)
          end
        end
      end),
    },
    vim.schedule_wrap(function(result)
      -- Process any remaining buffered data
      if stdout_buffer ~= '' then
        handle_line(stdout_buffer)
        stdout_buffer = ''
      end

      M.cleanup()
      if callbacks.on_exit then
        callbacks.on_exit(result.code or 0)
      end

      vim.notify('pi exited with code ' .. (result.code or 'unknown'), vim.log.levels.INFO)
    end)
  )

  if not ok or not process then
    vim.notify('Failed to spawn pi process: ' .. tostring(process), vim.log.levels.ERROR)
    return false
  end

  job_id = process
  vim.notify('pi started', vim.log.levels.INFO)
  return true
end

-- Stop the pi process
function M.stop()
  if not job_id then
    return
  end

  -- Send abort first
  M.send { type = 'abort' }

  -- Kill after brief delay
  vim.defer_fn(function()
    if job_id then
      pcall(function()
        job_id:kill(15) -- SIGTERM
      end)
    end
  end, 100)
end

-- Cleanup internal state
function M.cleanup()
  job_id = nil
  stdout_buffer = ''
end

-- Check if running
function M.is_running()
  if not job_id then
    return false
  end
  -- Check if process is still active
  local ok, is_closing = pcall(function()
    return job_id:is_closing()
  end)
  if ok then
    return not is_closing
  end
  return false
end

-- Get request that matches a predicate (for extension UI)
function M.get_pending_request(id)
  return pending_requests[id]
end

return M
