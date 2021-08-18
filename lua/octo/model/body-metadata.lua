local M = {}

---@class BodyMetadata
---@field savedBody string
---@field body string
---@field dirty boolean
---@field extmark integer|nil
---@field startLine integer
---@field endLine integer
---@field viewerCanUpdate boolean
-- @field reactionGroups table[]
-- @field reactionLine integer
local BodyMetadata = {}
BodyMetadata.__index = BodyMetadata

---BodyMetadata constructor.
---@return BodyMetadata
function BodyMetadata:new(opts)
  opts = opts or {}
  local this = {
    savedBody = opts.savedBody or "",
    body = opts.body or "",
    dirty = opts.dirty or false,
    extmark = opts.extmark or nil,
    viewerCanUpdate = opts.viewerCanUpdate or false,
    reactionLine = opts.reactionLine or false,
    reactionGroups = opts.reactionGroups or {},
  }
  setmetatable(this, self)
  return this
end

M.BodyMetadata = BodyMetadata

return M
