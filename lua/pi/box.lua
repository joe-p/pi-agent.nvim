-- pi.nvim Box utility module
-- Provides simple horizontal line separators

local M = {}

local default_width = 63 -- Default width for consistent line sizes

---Create a header line with a title
---@param title string The title to display in the header
---@return string The formatted header line
function M.header(title)
  if title and title ~= '' then
    local title_part = '─ ' .. title .. ' '
    local remaining = default_width - #title_part
    return title_part .. string.rep('─', remaining)
  else
    return string.rep('─', default_width)
  end
end

---Create the content prefix (now just empty)
---@return string Empty string
function M.content_prefix()
  return ''
end

---Create a content line (no prefix)
---@param text string The text content
---@return string The text as-is
function M.content_line(text)
  return text
end

---Pass through content without modification
---@param text string The text content
---@return string The text as-is
function M.content(text)
  return text
end

---Create a footer line
---@param footer string|nil The footer text (optional)
---@return string The formatted footer line
function M.footer(footer)
  if footer and footer ~= '' then
    local footer_part = '─ ' .. footer .. ' '
    local remaining = default_width - #footer_part
    return footer_part .. string.rep('─', remaining)
  else
    return string.rep('─', default_width)
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
    table.insert(lines, '')
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
    table.insert(lines, '')
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
