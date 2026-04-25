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

local default_width = 63 -- Default width for consistent box sizes

---Create a box header line with a title
---@param title string The title to display in the header
---@param style table|nil The style to use (defaults to single_round)
---@param width number|nil The width of the box (defaults to 63)
---@return string The formatted header line
function M.header(title, style, width)
  style = style or M.styles.single_round
  width = width or default_width
  local title_part = '─ ' .. title .. ' '
  local remaining = width - #title_part - 1
  return style.top .. title_part .. string.rep(style.right, remaining)
end

---Create the left border prefix for content lines
---@param style table|nil The style to use (defaults to single_round)
---@return string The left border character followed by a space
function M.content_prefix(style)
  style = style or M.styles.single_round
  return style.left .. ' '
end

---Create a content line with left border
---@param text string The text content
---@param style table|nil The style to use (defaults to single_round)
---@return string The formatted content line
function M.content_line(text, style)
  return M.content_prefix(style) .. text
end

---Create a box footer line
---@param footer string|nil The footer text (optional)
---@param style table|nil The style to use (defaults to single_round)
---@param width number|nil The width of the box (defaults to 63)
---@return string The formatted footer line
function M.footer(footer, style, width)
  style = style or M.styles.single_round
  width = width or default_width
  if footer and footer ~= '' then
    local footer_part = '─ ' .. footer .. ' '
    local remaining = width - #footer_part - 1
    return style.bottom .. footer_part .. string.rep(style.right, remaining)
  else
    return style.bottom .. string.rep(style.right, width - 1)
  end
end

---Create a complete box with header, content, and footer
---@param content string[]|string The content lines or single string
---@param opts table Options table with title, footer, style, width, empty_before, empty_after
---@return string[] Array of lines for the complete box
function M.box(content, opts)
  opts = opts or {}
  local style = opts.style or M.styles.single_round
  local width = opts.width or default_width
  local lines = {}

  -- Add empty line before if requested
  if opts.empty_before ~= false then
    table.insert(lines, '')
  end

  -- Header
  table.insert(lines, M.header(opts.title or '', style, width))

  -- Empty line after header (if no empty_after is false, for compact boxes)
  if opts.compact ~= true then
    table.insert(lines, M.content_prefix(style):sub(1, -2)) -- Just the border
  end

  -- Content
  if type(content) == 'string' then
    content = { content }
  end

  for _, line in ipairs(content) do
    -- Split multiline strings
    for _, subline in ipairs(vim.split(line, '\n', { plain = true })) do
      table.insert(lines, M.content_line(subline, style))
    end
  end

  -- Empty line before footer (if not compact)
  if opts.compact ~= true then
    table.insert(lines, M.content_prefix(style):sub(1, -2)) -- Just the border
  end

  -- Footer
  table.insert(lines, M.footer(opts.footer, style, width))

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
