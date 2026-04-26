-- pi.nvim input buffer

local M = {}

local buf = nil
local win = nil
local opts = {}

-- Require modules directly to avoid circular deps
local rpc = require 'pi.rpc'
local session = require 'pi.session'
local commands = require 'pi.commands'

function M.setup(config)
  opts = config
  -- Setup slash commands
  commands.setup(opts.commands)
end

function M.create()
  if buf and vim.api.nvim_buf_is_valid(buf) then
    return buf
  end

  -- Check if a buffer with this name already exists (e.g., from previous session)
  local existing_buf = vim.fn.bufexists 'pi-input://input' ~= 0 and vim.fn.bufnr 'pi-input://input' or -1
  if existing_buf ~= -1 and vim.api.nvim_buf_is_valid(existing_buf) then
    buf = existing_buf
  else
    buf = vim.api.nvim_create_buf(false, true)
    pcall(vim.api.nvim_buf_set_name, buf, 'pi-input://input')
    vim.api.nvim_set_option_value('filetype', 'piinput', { buf = buf })
    vim.api.nvim_set_option_value('buftype', 'nofile', { buf = buf })
    vim.api.nvim_set_option_value('bufhidden', 'hide', { buf = buf })
    vim.api.nvim_set_option_value('swapfile', false, { buf = buf })
    vim.api.nvim_set_option_value('modifiable', true, { buf = buf })
  end

  -- Always set up keymaps (buffer-local keymaps need to be set each time)
  M.setup_keymaps()

  -- Prompt placeholder
  M.set_placeholder 'Type your message here...'

  return buf
end

function M.get_buf()
  return buf
end

function M.configure_window(win_id)
  win = win_id
  vim.api.nvim_set_option_value('winfixheight', true, { win = win_id })
  vim.api.nvim_set_option_value('number', false, { win = win_id })
  vim.api.nvim_set_option_value('relativenumber', false, { win = win_id })
  vim.api.nvim_set_option_value('signcolumn', 'no', { win = win_id })
  vim.api.nvim_set_option_value('cursorline', true, { win = win_id })
  -- Window-local display options
  vim.api.nvim_set_option_value('wrap', true, { win = win_id })
  vim.api.nvim_set_option_value('linebreak', true, { win = win_id })
  vim.api.nvim_set_option_value('breakindent', true, { win = win_id })
end

function M.setup_keymaps()
  -- Toggle with close keymap (default: q)
  local close_key = opts.keymaps and opts.keymaps.close or 'q'
  vim.api.nvim_buf_set_keymap(buf, 'n', close_key, '<cmd>PiToggle<CR>', { noremap = true, silent = true })

  -- Send message with Enter in normal mode
  vim.api.nvim_buf_set_keymap(buf, 'n', '<CR>', '', {
    noremap = true,
    silent = true,
    callback = function()
      M.send_message(false)
    end,
  })

  local send_steering_key = opts.keymaps and opts.keymaps.send_steering or '<S-CR>'
  -- Send steering message with Shift+Enter (or a different key for terminal compatibility)
  vim.api.nvim_buf_set_keymap(buf, 'i', send_steering_key, '', {
    noremap = true,
    silent = true,
    callback = function()
      M.send_message(true)
    end,
  })

  -- Also provide a command version for terminals without Shift+Enter
  vim.api.nvim_buf_set_keymap(buf, 'n', '<C-s>', '', {
    noremap = true,
    silent = true,
    callback = function()
      M.send_message(true)
    end,
  })

  -- Cancel / abort operation (configurable)
  local cancel_key = opts.keymaps and opts.keymaps.cancel or '<C-x>'
  vim.api.nvim_buf_set_keymap(buf, 'n', cancel_key, '', {
    noremap = true,
    silent = true,
    callback = function()
      rpc.send { type = 'abort' }
    end,
  })

  -- Clear on <C-c> (skip if it conflicts with cancel key)
  if cancel_key ~= '<C-c>' then
    vim.api.nvim_buf_set_keymap(buf, 'n', '<C-c>', '', {
      noremap = true,
      silent = true,
      callback = function()
        M.clear()
      end,
    })
  end

  -- @ file reference support
  vim.api.nvim_buf_set_keymap(buf, 'i', '@', '', {
    noremap = true,
    silent = true,
    callback = function()
      -- Insert @ immediately and open file picker
      local row, col = unpack(vim.api.nvim_win_get_cursor(0))
      local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ''
      vim.api.nvim_buf_set_lines(buf, row - 1, row, false, { line:sub(1, col) .. '@' .. line:sub(col + 1) })
      vim.api.nvim_win_set_cursor(0, { row, col + 1 })
      vim.defer_fn(function()
        M.open_file_picker()
      end, 100)
    end,
  })

  -- New session
  vim.api.nvim_buf_set_keymap(buf, 'n', '<C-n>', '', {
    noremap = true,
    silent = true,
    callback = function()
      rpc.send { type = 'new_session' }
      -- Clear chat via UI
      local ui = require 'pi.ui'
      ui.clear_chat()
    end,
  })

  -- File reference in normal mode
  vim.api.nvim_buf_set_keymap(buf, 'n', '@', '', {
    noremap = true,
    silent = true,
    callback = function()
      -- Insert @ and open file picker
      local row, col = unpack(vim.api.nvim_win_get_cursor(0))
      local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ''
      vim.api.nvim_buf_set_lines(buf, row - 1, row, false, { line:sub(1, col) .. '@' .. line:sub(col + 1) })
      vim.api.nvim_win_set_cursor(0, { row, col + 1 })
      M.open_file_picker()
    end,
  })

  -- Slash command help
  local help_key = opts.keymaps and opts.keymaps.slash_help or '?'
  vim.api.nvim_buf_set_keymap(buf, 'n', help_key, '', {
    noremap = true,
    silent = true,
    callback = function()
      commands.show_help()
    end,
  })
end

function M.send_message(steering)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  -- Get all lines
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local text = table.concat(lines, '\n')

  -- Trim whitespace
  text = vim.trim(text)

  -- Don't send empty messages
  if text == '' then
    return
  end

  -- Handle client-side slash commands
  if text:match '^/resume' then
    M.show_session_picker()
    M.clear()
    return
  end

  if text:match '^/new' then
    local pi = require 'pi'
    pi.new_session()
    M.clear()
    return
  end

  if text:match '^/model' then
    M.show_model_picker()
    M.clear()
    return
  end

  -- Other slash commands are handled by pi
  -- They are sent just like normal messages, pi parses and executes them

  -- Build command
  local state = session.get_state()
  local cmd = {
    type = 'prompt',
    message = text,
  }

  -- Add streaming behavior if agent is busy
  if state and state.isStreaming then
    cmd.streamingBehavior = steering and 'steer' or 'followUp'
  end

  -- Send via RPC
  rpc.send(cmd)

  -- Add to UI
  local ui = require 'pi.ui'
  ui.add_user_message(text)

  -- Clear buffer
  M.clear()
end

function M.clear()
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
end

function M.set_placeholder(text)
  -- Can use virtual text for placeholder
  -- For now, just leave empty
end

function M.open_file_picker()
  -- Use built-in file picker
  vim.ui.select(vim.fn.glob('**/*', true, true), {
    prompt = 'Select file:',
  }, function(choice)
    if choice then
      M.insert_file_ref(choice)
    end
  end)
end

function M.insert_file_ref(filepath)
  -- Get cursor position
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ''

  -- The @ was inserted just before opening the picker. When the picker takes
  -- focus we leave insert mode, which shifts the cursor back one column onto
  -- the @ itself. Detect that case and insert *after* the @ so the result is
  -- "@filepath" rather than "filepath@".
  local insert_col = col
  if line:sub(col + 1, col + 1) == '@' then
    insert_col = col + 1
  end

  local before = line:sub(1, insert_col)
  local after = line:sub(insert_col + 1)
  vim.api.nvim_buf_set_lines(buf, row - 1, row, false, { before .. filepath .. after })
  vim.api.nvim_win_set_cursor(0, { row, insert_col + #filepath })
  -- Pickers exit to normal mode; return to insert mode
  vim.cmd 'startinsert'
end

function M.focus()
  -- Find window with input buffer and focus it
  for _, win_id in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win_id) == buf then
      vim.api.nvim_set_current_win(win_id)
      -- Enter insert mode
      vim.cmd 'startinsert'
      return
    end
  end
end

-- Get current content
function M.get_content()
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return ''
  end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  return table.concat(lines, '\n')
end

-- Decode pi's session directory naming (--path--to--dir format)
local function decode_session_dir(dirname)
  -- Remove leading and trailing -- if present
  local decoded = dirname:gsub('^%-%-', ''):gsub('%-%-$', '')
  -- Replace -- with / to reconstruct path
  decoded = decoded:gsub('%-%-', '/')
  -- Handle special case for home directory
  decoded = decoded:gsub('^/Users/([^/]+)', '~')
  decoded = decoded:gsub('^/home/([^/]+)', '~')
  return decoded
end

-- Extract first user message from a JSONL session file
local function get_first_user_message(filepath)
  local f = io.open(filepath, 'r')
  if not f then
    return nil
  end

  -- Read file line by line to find user message
  for line in f:lines() do
    local ok, data = pcall(vim.json.decode, line)
    if ok and data and data.message and data.message.role == 'user' and data.message.content then
      f:close()
      -- Concatenate text from content array
      local parts = {}
      if type(data.message.content) == 'table' then
        for _, part in ipairs(data.message.content) do
          if part.type == 'text' and part.text then
            table.insert(parts, part.text)
          end
        end
      else
        table.insert(parts, tostring(data.message.content))
      end
      local msg = table.concat(parts, ' '):gsub('\n', ' '):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
      if #msg > 60 then
        msg = msg:sub(1, 57) .. '...'
      end
      return msg ~= '' and msg or nil
    end
  end

  f:close()
  return nil
end

-- Show model picker and switch to selected model
function M.show_model_picker()
  rpc.send({ type = 'get_available_models' }, function(response)
    if not response or not response.success or not response.data or not response.data.models then
      vim.notify('Failed to fetch models', vim.log.levels.ERROR)
      return
    end

    local models = response.data.models
    if #models == 0 then
      vim.notify('No models available', vim.log.levels.WARN)
      return
    end

    -- Sort models by provider then name
    table.sort(models, function(a, b)
      local provider_a = a.provider or ''
      local provider_b = b.provider or ''
      if provider_a ~= provider_b then
        return provider_a:lower() < provider_b:lower()
      end
      return (a.name or a.id or ''):lower() < (b.name or b.id or ''):lower()
    end)

    -- Build display items
    local items = {}
    for _, model in ipairs(models) do
      local display = string.format('%s / %s', model.provider or 'unknown', model.name or model.id)
      table.insert(items, {
        display = display,
        model = model,
      })
    end

    vim.ui.select(items, {
      prompt = 'Select model:',
      format_item = function(item)
        return item.display
      end,
    }, function(choice)
      if not choice then
        return
      end

      local model = choice.model
      rpc.send({ type = 'set_model', provider = model.provider, modelId = model.id }, function(set_response)
        if set_response and set_response.success then
          local name = set_response.data and (set_response.data.name or set_response.data.id) or model.name or model.id
          vim.notify('Switched to model: ' .. name, vim.log.levels.INFO)
          -- Refresh state so session module knows about the new model
          rpc.send { type = 'get_state' }
        else
          local err = set_response and set_response.error or 'Unknown error'
          vim.notify('Failed to switch model: ' .. err, vim.log.levels.ERROR)
        end
      end)
    end)
  end)
end

-- Show session picker and switch to selected session
function M.show_session_picker()
  -- Determine session directory - pi stores sessions in ~/.pi/agent/sessions/
  local session_dir = opts.session_dir
  if not session_dir then
    -- Default pi session directory with subdirs for each cwd
    session_dir = vim.fn.expand '~/.pi/agent/sessions'
  end

  if vim.fn.isdirectory(session_dir) == 0 then
    vim.notify('No session directory found: ' .. session_dir, vim.log.levels.WARN)
    return
  end

  -- Find all .jsonl session files recursively in subdirectories
  local files = {}
  local scan_dir = vim.fs.dir and vim.fs.dir or vim.fn.glob

  -- Use vim.fs.find if available (Neovim 0.10+)
  if vim.fs then
    for name, type in vim.fs.dir(session_dir) do
      if type == 'directory' then
        local subdir = session_dir .. '/' .. name
        for subname, subtype in vim.fs.dir(subdir) do
          if subtype == 'file' and subname:match '%.jsonl$' then
            table.insert(files, subdir .. '/' .. subname)
          end
        end
      end
    end
  else
    -- Fallback for older Neovim
    local pattern = session_dir .. '/*/*.jsonl'
    files = vim.fn.glob(pattern, false, true)
  end

  if #files == 0 then
    vim.notify('No sessions found in ' .. session_dir, vim.log.levels.WARN)
    return
  end

  -- Sort by modification time (newest first)
  table.sort(files, function(a, b)
    local stat_a = vim.loop.fs_stat and vim.loop.fs_stat(a) or nil
    local stat_b = vim.loop.fs_stat and vim.loop.fs_stat(b) or nil
    if stat_a and stat_b then
      return stat_a.mtime.sec > stat_b.mtime.sec
    end
    return a > b
  end)

  -- Create display items with first user message
  local items = {}
  for _, filepath in ipairs(files) do
    local dir_name = vim.fn.fnamemodify(vim.fn.fnamemodify(filepath, ':h'), ':t')
    local filename = vim.fn.fnamemodify(filepath, ':t:r')
    local decoded_path = decode_session_dir(dir_name)

    -- Get first user message for display
    local first_message = get_first_user_message(filepath)

    local stat = vim.loop.fs_stat and vim.loop.fs_stat(filepath) or nil
    local size_str = ''
    if stat then
      local kb = math.floor(stat.size / 1024)
      if kb > 1024 then
        size_str = string.format(' (%.1f MB)', kb / 1024)
      else
        size_str = string.format(' (%d KB)', kb)
      end
    end

    local display
    if first_message then
      -- Show first user message as primary, path as secondary
      display = first_message .. size_str
    elseif filename == 'session' then
      -- Default session name, no user message found
      display = decoded_path .. size_str
    else
      -- Named session, no user message found
      display = decoded_path .. ' - ' .. filename .. size_str
    end

    table.insert(items, {
      path = filepath,
      display = display,
      cwd = decoded_path,
      filename = filename,
    })
  end

  -- Show picker
  vim.ui.select(items, {
    prompt = 'Select session:',
    format_item = function(item)
      return item.display
    end,
  }, function(choice)
    if choice then
      -- Use the pi module to handle session switching with message loading
      local pi = require 'pi'

      -- Send switch_session command
      rpc.send({ type = 'switch_session', sessionPath = choice.path }, function(response)
        if response and response.success then
          -- Load messages and refresh
          pi.load_session_messages(choice.path)
          vim.notify('Switched to session: ' .. choice.cwd, vim.log.levels.INFO)
        else
          vim.notify('Failed to switch session', vim.log.levels.ERROR)
        end
      end)
    end
  end)
end

return M
