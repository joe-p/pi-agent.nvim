-- pi.nvim slash commands
-- Commands are provided by the pi agent and extensions via get_commands
-- They are executed by sending them to the prompt command

local M = {}

local commands = {} -- List of available commands from pi
local commands_by_name = {} -- Index by name

-- Check if text is a slash command
function M.is_command(text)
  if not text or text == '' then
    return false
  end
  return text:match '^/' ~= nil
end

-- Fetch commands from pi agent
-- callback(results) - called with list of commands
function M.fetch(rpc, callback)
  rpc.send({ type = 'get_commands' }, function(response)
    if response and response.success and response.data and response.data.commands then
      commands = response.data.commands or {}
      commands_by_name = {}

      for _, cmd in ipairs(commands) do
        if cmd.name then
          commands_by_name[cmd.name] = cmd
        end
      end

      if callback then
        callback(commands)
      end
    else
      if callback then
        callback({})
      end
    end
  end)
end

-- Get cached commands
function M.get_all()
  return vim.deepcopy(commands)
end

-- Get a specific command by name
function M.get(name)
  return commands_by_name[name] and vim.deepcopy(commands_by_name[name]) or nil
end

-- Check if a command exists
function M.exists(name)
  if name:sub(1, 1) == '/' then
    name = name:sub(2)
  end
  return commands_by_name[name] ~= nil
end

-- Get command display info for UI
-- Returns { name, description, source }
function M.get_info(text)
  if not M.is_command(text) then
    return nil
  end

  local name = text:match '^/([^%s]+)'
  if not name then
    return nil
  end

  local cmd = commands_by_name[name]
  if cmd then
    return {
      name = cmd.name,
      description = cmd.description or '',
      source = cmd.source or 'unknown', -- "extension", "prompt", "skill"
      path = cmd.path,
    }
  end

  return nil
end

-- Show help window with available commands
function M.show_help()
  local lines = { '# Slash Commands', '' }

  if #commands == 0 then
    table.insert(lines, '*No commands available. Start pi to load commands.*')
  else
    -- Group by source
    local by_source = {}
    for _, cmd in ipairs(commands) do
      local source = cmd.source or 'unknown'
      if not by_source[source] then
        by_source[source] = {}
      end
      table.insert(by_source[source], cmd)
    end

    for source, cmds in pairs(by_source) do
      table.insert(lines, '## ' .. source:gsub('^%l', string.upper))
      table.insert(lines, '')

      table.sort(cmds, function(a, b)
        return a.name:lower() < b.name:lower()
      end)

      for _, cmd in ipairs(cmds) do
        local desc = cmd.description or ''
        table.insert(lines, string.format('- **/%s** - %s', cmd.name, desc))
      end
      table.insert(lines, '')
    end
  end

  -- Show in floating window
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value('filetype', 'markdown', { buf = buf })
  vim.api.nvim_set_option_value('modifiable', false, { buf = buf })

  local width = math.min(80, vim.o.columns - 4)
  local height = math.min(#lines + 4, vim.o.lines - 4)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local opts = {
    relative = 'editor',
    row = row,
    col = col,
    width = width,
    height = height,
    style = 'minimal',
    border = 'rounded',
    title = ' Pi Commands ',
    title_pos = 'center',
  }

  local win = vim.api.nvim_open_win(buf, true, opts)

  -- Close on keys
  vim.keymap.set('n', 'q', function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf, silent = true })
  vim.keymap.set('n', '<Esc>', function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf, silent = true })
end

-- Get commands as completion items
-- prefix should be the text after /
function M.get_completions(prefix)
  prefix = prefix or ''
  local matches = {}

  for _, cmd in ipairs(commands) do
    local name = cmd.name or ''
    if prefix == '' or name:lower():match('^' .. vim.pesc(prefix:lower())) then
      table.insert(matches, {
        name = name,
        description = cmd.description or '',
        source = cmd.source or '',
      })
    end
  end

  table.sort(matches, function(a, b)
    return a.name:lower() < b.name:lower()
  end)

  return matches
end

-- Clear cached commands (e.g., on new session)
function M.clear()
  commands = {}
  commands_by_name = {}
end

-- Setup function (called during initialization)
function M.setup(config)
  -- Commands module is mostly self-contained
  -- Config can be extended for future command-related settings
end

return M
