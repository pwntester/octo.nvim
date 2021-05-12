local M = {}

---@class ThreadMetadata
---@field threadId string
---@field replyTo string
---@field reviewId string
local ThreadMetadata = {}
ThreadMetadata.__index = ThreadMetadata

---ThreadMetadata constructor.
---@return ThreadMetadata
function ThreadMetadata:new(opts)
  local this = {
    threadId = opts.threadId,
    replyTo = opts.replyTo,
    reviewId = opts.reviewId
  }
  setmetatable(this, self)
  return this
end

M.ThreadMetadata = ThreadMetadata

return M
