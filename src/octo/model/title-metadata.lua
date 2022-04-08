local M = {}

---@class TitleMetadata
---@field savedBody string
---@field body string
---@field dirty boolean
---@field extmark integer|nil
---@field startLine integer
---@field endLine integer
local TitleMetadata = {}
TitleMetadata.__index = TitleMetadata

---TitleMetadata constructor.
---@return TitleMetadata
function TitleMetadata:new(opts)
  opts = opts or {}
  local this = {
    savedBody = opts.savedBody or "",
    body = opts.body or "",
    dirty = opts.dirty or false,
    extmark = opts.extmark or nil,
  }

  setmetatable(this, self)
  return this
end
M.TitleMetadata = TitleMetadata

return M
