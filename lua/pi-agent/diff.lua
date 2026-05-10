-- Diff rendering functionality for pi-agent.nvim
-- Ported from opencode.nvim https://github.com/sudo-tee/opencode.nvim/blob/29d43526f88157cd4edd071b899dd01f240b771b/LICENSE

local M = {}

-- Namespace for diff extmarks
M.ns = vim.api.nvim_create_namespace 'pi_agent_diff'

---Parse unified diff to extract line numbers from hunk headers
---@param lines string[] The diff lines to parse
---@return table<number, {old: number|nil, new: number|nil}> numbered_lines Map of line index to old/new line numbers
---@return number line_number_width Maximum width needed for line numbers
local function parse_diff_line_numbers(lines)
  local numbered_lines = {}
  local old_line
  local new_line
  local max_line_number = 0

  for idx, line in ipairs(lines) do
    -- Match hunk headers like "@@ -1,3 +1,4 @@" or "@@ -0,0 +1 @@"
    local old_start, new_start = line:match '^@@ %-(%d+),?%d* %+(%d+),?%d* @@'

    if old_start and new_start then
      old_line = tonumber(old_start)
      new_line = tonumber(new_start)
    elseif old_line and new_line then
      local first_char = line:sub(1, 1)

      if first_char == ' ' then
        -- Context line (unchanged)
        numbered_lines[idx] = { old = old_line, new = new_line }
        max_line_number = math.max(max_line_number, old_line, new_line)
        old_line = old_line + 1
        new_line = new_line + 1
      elseif first_char == '+' and not line:match '^%+%+%+%s' then
        -- Added line (not a "+++ filename" header)
        numbered_lines[idx] = { old = nil, new = new_line }
        max_line_number = math.max(max_line_number, new_line)
        new_line = new_line + 1
      elseif first_char == '-' and not line:match '^%-%-%-%s' then
        -- Deleted line (not a "--- filename" header)
        numbered_lines[idx] = { old = old_line, new = nil }
        max_line_number = math.max(max_line_number, old_line)
        old_line = old_line + 1
      end
    end
  end

  return numbered_lines, #tostring(max_line_number)
end

---Build the gutter text with line numbers
---@param line_numbers {old: number|nil, new: number|nil}
---@param width number Width for padding
---@return string
local function build_diff_gutter(line_numbers, width)
  local line_number = line_numbers.new or line_numbers.old
  return string.format('%' .. width .. 's', line_number and tostring(line_number) or '')
end

---Add a single diff line with gutter and highlighting
---@param bufnr number Buffer number
---@param line string The diff line content
---@param line_numbers {old: number|nil, new: number|nil} Line number info
---@param width number Gutter width
---@return number line_idx The index of the added line
local function add_diff_line(bufnr, line, line_numbers, width)
  local first_char = line:sub(1, 1)

  -- Determine highlight groups
  local line_hl = first_char == '+' and 'PiAgentDiffAdd' or first_char == '-' and 'PiAgentDiffDelete' or nil

  local gutter_hl = first_char == '+' and 'PiAgentDiffAddGutter' or first_char == '-' and 'PiAgentDiffDeleteGutter' or 'PiAgentDiffGutter'

  local sign_hl = gutter_hl

  -- Build gutter with line number
  local gutter = build_diff_gutter(line_numbers, width)
  local gutter_width = #gutter + 2

  -- Content without the +/- prefix
  local content = line:sub(2)

  -- Add the line with indentation for the gutter
  local line_idx = vim.api.nvim_buf_line_count(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, line_idx, line_idx, false, { string.rep(' ', gutter_width) .. content })

  -- Add extmark for the gutter overlay
  local extmark = {
    virt_text = {
      { gutter, gutter_hl },
      { first_char, sign_hl },
      { ' ', gutter_hl },
    },
    virt_text_pos = 'overlay',
    priority = 5000,
  }

  -- Apply line highlighting if applicable
  if line_hl then
    extmark.hl_group = line_hl
    extmark.hl_eol = true
  end

  vim.api.nvim_buf_set_extmark(bufnr, M.ns, line_idx, 0, extmark)

  return line_idx
end

---Format and render a unified diff in the buffer
---@param bufnr number Buffer number to render into
---@param diff string The unified diff content
---@param file_type? string Optional file type for code block (e.g., 'lua', 'python')
---@param append_fn? function Optional function to append lines (defaults to vim.api.nvim_buf_set_lines)
function M.render_diff(bufnr, diff, file_type, append_fn)
  file_type = file_type or ''
  append_fn = append_fn
    or function(lines)
      local count = vim.api.nvim_buf_line_count(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, count, count, false, lines)
    end

  -- Split diff into lines
  local full_lines = vim.split(diff, '\n', { plain = true })

  -- Parse line numbers from hunk headers
  local numbered_lines, line_number_width = parse_diff_line_numbers(full_lines)

  -- Skip first 5 lines for large diffs (header lines like --- a/file, +++ b/file, etc.)
  local first_visible_line = #full_lines > 5 and 6 or 1
  local lines = first_visible_line > 1 and vim.list_slice(full_lines, first_visible_line) or full_lines

  -- Add opening fence
  append_fn { '`````' .. file_type }

  -- Process each line
  for idx, line in ipairs(lines) do
    local source_idx = first_visible_line + idx - 1
    if numbered_lines[source_idx] then
      add_diff_line(bufnr, line, numbered_lines[source_idx], line_number_width)
    else
      -- Header lines or other non-diff content
      append_fn { line }
    end
  end

  -- Add closing fence
  append_fn { '`````' }
end

---Parse diff to get statistics (additions/deletions per file)
---@param diff string The unified diff
---@return table<string, {additions: number, deletions: number}> stats
function M.get_diff_stats(diff)
  local stats = {}
  local current_file = nil

  for line in diff:gmatch '[^\r\n]+' do
    -- File headers
    local file_a = line:match '^%-%-%- ([ab]/(.+))'
    local file_b = line:match '^%+%+%+ ([ab]/(.+))'

    if file_b then
      current_file = file_b:gsub('^[ab]/', '')
      if not stats[current_file] then
        stats[current_file] = { additions = 0, deletions = 0 }
      end
    elseif file_a then
      current_file = file_a:gsub('^[ab]/', '')
      if not stats[current_file] then
        stats[current_file] = { additions = 0, deletions = 0 }
      end
    -- Count additions (lines starting with + but not +++)
    elseif line:sub(1, 1) == '+' and not line:match '^%+%+%+' then
      if current_file then
        stats[current_file].additions = stats[current_file].additions + 1
      end
    -- Count deletions (lines starting with - but not ---)
    elseif line:sub(1, 1) == '-' and not line:match '^%-%-%-' then
      if current_file then
        stats[current_file].deletions = stats[current_file].deletions + 1
      end
    end
  end

  return stats
end

---Setup highlight groups for diff rendering
---Should be called during plugin setup
function M.setup_highlights()
  -- Diff Add - green background
  vim.api.nvim_set_hl(0, 'PiAgentDiffAdd', {
    bg = '#2d4a22',
    fg = '#a8d5a2',
  })

  -- Diff Delete - red background
  vim.api.nvim_set_hl(0, 'PiAgentDiffDelete', {
    bg = '#4a2222',
    fg = '#d5a2a2',
  })

  -- Gutter highlights
  vim.api.nvim_set_hl(0, 'PiAgentDiffAddGutter', {
    bg = '#3d5a32',
    fg = '#88c578',
    bold = true,
  })

  vim.api.nvim_set_hl(0, 'PiAgentDiffDeleteGutter', {
    bg = '#5a3232',
    fg = '#c57878',
    bold = true,
  })

  vim.api.nvim_set_hl(0, 'PiAgentDiffGutter', {
    fg = '#666666',
  })
end

return M
