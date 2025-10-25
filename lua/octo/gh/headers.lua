---@class octo.Headers
---@field json string
---@field diff string
---@field raw string

---@type octo.Headers
local M = {
  json = "Accept: application/vnd.github.v3+json",
  diff = "Accept: application/vnd.github.v3.diff",
  raw = "Accept: application/vnd.github.v3.raw",
}

return M
