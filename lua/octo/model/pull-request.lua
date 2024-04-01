local utils = require "octo.utils"
local backend = require "octo.backend"

local M = {}

---@class PullRequest
---@field repo string
---@field owner string
---@field name string
---@field number integer
---@field id string
---@field bufnr integer
---@field left Rev
---@field right Rev
---@field local_right boolean
---@field local_left boolean
---@field files table
---@field diff string
local PullRequest = {}
PullRequest.__index = PullRequest

---PullRequest constructor.
---@return PullRequest
function PullRequest:new(opts)
  local this = {
    -- TODO: rename to nwo
    repo = opts.repo,
    number = opts.number,
    owner = "",
    name = "",
    id = opts.id,
    left = opts.left,
    right = opts.right,
    local_right = false,
    local_left = false,
    bufnr = opts.bufnr,
    diff = "",
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

  self:get_diff(this)

  return this
end

M.PullRequest = PullRequest

---Fetch the diff of the PR
function PullRequest:get_diff(pr)
  local func = backend.get_funcs()["pr_get_diff"]
  pr.diff = func(pr.repo, pr.number)
end

---Fetch the changed files for a given PR
function PullRequest:get_changed_files(callback)
  local func = backend.get_funcs()["pr_get_changed_files"]
  func(self, callback)
end

---Fetch the changed files at a given commit
function PullRequest:get_commit_changed_files(rev, callback)
  local func = backend.get_funcs()["pr_get_commit_changed_files"]
  func(self, rev, callback)
end

return M
