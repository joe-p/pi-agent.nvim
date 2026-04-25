-- pi.nvim Box utility module
-- Provides consistent box-drawing style for UI elements

local M = {}

-- Box style configuration
M.styles = {
  single = { top = '┌', right = '─', bottom = '└', left = '│', corner_tr = '┐', corner_br = '┘', branch_down = '┬', branch_up = '┴' },
  single_round = { top = '╭', right = '─', bottom = '╰', left = '│', corner_tr = '╮', corner_br = '╯', branch_down = '┬', branch_up = '┴' },
  double = { top = '╔', right = '═', bottom = '╚', left = '║', corner_tr = '╗', corner_br = '╝', branch_down = '╦', branch_up = '╩' },
  solid = { left = '▌', right = '▐' },
}

local style = M.styles.single
local default_width = 63 -- Default width for consistent box sizes

---Create a box header line with a title
---@param title string The title to display in the header
---@return string The formatted header line
function M.header(title)
  local title_part = '─ ' .. title .. ' '
  local remaining = default_width - #title_part - 1
  return style.top .. title_part .. string.rep(style.right, remaining)
end

---Create the left border prefix for content lines
---@return string The left border character followed by a space
function M.content_prefix()
  return style.left .. ' '
end

---Create a content line with left border
---@param text string The text content
---@return string The formatted content line
function M.content_line(text)
  return M.content_prefix() .. text
end

---Create a box footer line
---@param footer string|nil The footer text (optional)
---@return string The formatted footer line
function M.footer(footer)
  if footer and footer ~= '' then
    local footer_part = '─ ' .. footer .. ' '
    local remaining = default_width - #footer_part - 1
    return style.bottom .. footer_part .. string.rep(style.right, remaining)
  else
    return style.bottom .. string.rep(style.right, default_width - 1)
  end
end

---Create a complete box with header, content, and footer
---@param content string[]|string The content lines or single string
---@param opts table Options table with title, footer, empty_before, empty_after
---@return string[] Array of lines for the complete box
function M.box(content, opts)
  opts = opts or {}
  local lines = {}

  -- Add empty line before if requested
  if opts.empty_before ~= false then
    table.insert(lines, '')
  end

  -- Header
  table.insert(lines, M.header(opts.title or ''))

  -- Empty line after header (if no empty_after is false, for compact boxes)
  if opts.compact ~= true then
    table.insert(lines, M.content_prefix():sub(1, -2)) -- Just the border
  end

  -- Content
  if type(content) == 'string' then
    content = { content }
  end

  for _, line in ipairs(content) do
    -- Split multiline strings
    for _, subline in ipairs(vim.split(line, '\n', { plain = true })) do
      table.insert(lines, M.content_line(subline))
    end
  end

  -- Empty line before footer (if not compact)
  if opts.compact ~= true then
    table.insert(lines, M.content_prefix():sub(1, -2)) -- Just the border
  end

  -- Footer
  table.insert(lines, M.footer(opts.footer))

  -- Add empty line after if requested
  if opts.empty_after ~= false then
    table.insert(lines, '')
  end

  return lines
end

---Create a simple info line (for spinners, compact messages)
---@param text string The text to display
---@return string[] Array containing the line
function M.info_line(text)
  return { '', '-- ' .. text .. ' --', '' }
end

return M
