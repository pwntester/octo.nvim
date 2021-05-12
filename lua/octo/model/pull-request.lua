local util = require"octo.util"

local M = {}

---@class PullRequest
---@field repo string
---@field number integer
---@field id string
---@field left Rev
---@field right Rev
local PullRequest = {}
PullRequest.__index = PullRequest

---PullRequest constructor.
---@return PullRequest
function PullRequest:new(opts)
  local this = {
    repo = opts.repo,
    number = opts.number,
    id = opts.id,
    left = opts.left,
    right = opts.right
  }
  this.owner, this.name = util.split_repo(this.repo)
  setmetatable(this, self)
  return this
end

M.PullRequest = PullRequest

return M
