local utils = require "octo.utils"

local M = {}

---@class PullRequest
---@field repo string
---@field number integer
---@field id string
---@field bufnr integer
---@field left Rev
---@field right Rev
---@field files table
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
    right = opts.right,
    local_right = false,
    local_left = false,
    bufnr = opts.bufnr,
  }
  this.files = {}
  for _, file in ipairs(opts.files) do
    this.files[file.path] = file.viewerViewedState
  end
  this.owner, this.name = utils.split_repo(this.repo)
  utils.commit_exists(this.right.commit, function(exists)
    this.local_right = exists
  end)
  utils.commit_exists(this.left.commit, function(exists)
    this.local_left = exists
  end)

  setmetatable(this, self)
  return this
end

M.PullRequest = PullRequest

return M
