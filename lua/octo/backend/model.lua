local M = {}

---@class Backend
local Backend = {}

---Backend constructor.
---@return Backend 
function Backend:new(opts)
  opts = opts or {}
  setmetatable(opts, self)
  self.__index = self
  return opts
end

M.Backend = Backend

function M.available_executables()
    if vim.fn.executable "gh" then
        return true
    end

    if vim.fn.executable "glab" then
        return true
    end

    return false
end

return M
