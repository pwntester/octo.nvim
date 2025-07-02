local M = {}

---@class ThreadMetadata
---@field threadId string
---@field replyTo string
---@field replyToRest string?
---@field reviewId string
---@field path string
---@field line number
---@field bufferStartLine? integer
---@field bufferEndLine? integer
local ThreadMetadata = {}
ThreadMetadata.__index = ThreadMetadata

---ThreadMetadata constructor.
---@return ThreadMetadata
function ThreadMetadata:new(opts)
  ---@type ThreadMetadata
  local this = {
    threadId = opts.threadId,
    replyTo = opts.replyTo,
    replyToRest = opts.replyToRest,
    reviewId = opts.reviewId,
    path = opts.path,
    line = opts.line,
  }
  setmetatable(this, self)
  return this
end

M.ThreadMetadata = ThreadMetadata

return M
