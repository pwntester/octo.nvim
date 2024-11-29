-- Heavily derived from `diffview.nvim`:
-- https://github.com/sindrets/diffview.nvim/blob/main/lua/diffview/rev.lua
--
local M = {}

---@class Rev
---@field type integer
---@field commit string
---@field head boolean
local Rev = {}
Rev.__index = Rev

---Rev constructor
---@param commit string
---@return Rev
function Rev:new(commit, head)
  local this = {
    commit = commit,
    head = head or false,
  }
  setmetatable(this, self)
  return this
end

function Rev:abbrev()
  return self.commit:sub(1, 7)
end

M.Rev = Rev

return M
