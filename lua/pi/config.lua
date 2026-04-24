-- pi.nvim configuration

local M = {}

M.options = {}

function M.setup(opts)
  M.options = opts or {}
end

function M.get(key)
  return M.options[key]
end

return M