local M = {}

---@class ThreadMetadata
---@field threadId string
---@field replyTo string
---@field reviewId string
---@field path string
---@field line number
local ThreadMetadata = {}
ThreadMetadata.__index = ThreadMetadata

---ThreadMetadata constructor.
---@return ThreadMetadata
function ThreadMetadata:new(opts)
  local this = {
    threadId = opts.threadId,
    replyTo = opts.replyTo,
    reviewId = opts.reviewId,
    path = opts.path,
    line = opts.line,
  }
  setmetatable(this, self)
  return this
end

M.ThreadMetadata = ThreadMetadata

return M
