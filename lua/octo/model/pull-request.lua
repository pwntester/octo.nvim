local utils = require "octo.utils"
local gh = require "octo.gh"

local M = {}

---https://docs.github.com/en/graphql/reference/enums#fileviewedstate
---@alias ViewedState "DISMISSED" | "VIEWED" | "UNVIEWED"

---@class PullRequest
---@field repo string
---@field head_repo string
---@field head_ref_name string
---@field owner string
---@field name string
---@field number integer
---@field id string
---@field bufnr integer
---@field left Rev
---@field right Rev
---@field local_right boolean
---@field local_left boolean
---@field files {[string]: ViewedState}
---@field diff string
local PullRequest = {}
PullRequest.__index = PullRequest

---@class PullRequestOpts
---@field repo string
---@field head_repo string
---@field head_ref_name string
---@field number integer
---@field id string
---@field left Rev
---@field right Rev
---@field bufnr? integer
---@field files { path: string, viewerViewedState: ViewedState }[]

---PullRequest constructor.
---@param opts PullRequestOpts
---@return PullRequest
function PullRequest:new(opts)
  ---@type PullRequest
  local this = {
    repo = opts.repo,
    head_repo = opts.head_repo,
    head_ref_name = opts.head_ref_name,
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
    files = {},
  }
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

---@param data any[]
local function merge_pages(data)
  local out = {} ---@type table<any, any>
  for _, page in ipairs(data) do
    if type(page) == "table" then
      -- Check if page is array-like or object-like
      if #page > 0 then
        -- Array-like, use ipairs
        for _, item in
          ipairs(page --[[@as any[] ]])
        do
          table.insert(out, item)
        end
      else
        -- Object-like: merge its key/value pairs directly into out
        for k, v in
          pairs(page --[[@as table<any, any>]])
        do
          out[k] = v
        end
      end
    end
  end
  return out
end

--- Fetch the diff of the PR
--- @param pr PullRequest
function PullRequest:get_diff(pr)
  local url = string.format("repos/%s/pulls/%d", pr.repo, pr.number)
  gh.run {
    args = { "api", "--paginate", url },
    headers = { "Accept: application/vnd.github.v3.diff" },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
      elseif output then
        pr.diff = output
      end
    end,
  }
end

---Fetch the changed files for a given PR
---@param callback fun(files: FileEntry[]): nil
function PullRequest:get_changed_files(callback)
  local url = string.format("repos/%s/pulls/%d/files", self.repo, self.number)
  gh.run {
    args = { "api", "--paginate", url, "--slurp" },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
      elseif output then
        local FileEntry = require("octo.reviews.file-entry").FileEntry
        local results = vim.json.decode(output)
        ---@type {
        ---  filename: string,
        ---  previous_filename: string,
        ---  patch: string,
        ---  status: string,
        ---  additions: integer,
        ---  deletions: integer,
        ---  changes: integer,
        ---}[]
        results = merge_pages(results)
        local files = {}
        for _, result in ipairs(results) do
          local entry = FileEntry:new {
            path = result.filename,
            previous_path = result.previous_filename,
            patch = result.patch,
            pull_request = self,
            status = utils.file_status_map[result.status],
            stats = {
              additions = result.additions,
              deletions = result.deletions,
              changes = result.changes,
            },
          }
          table.insert(files, entry)
        end
        callback(files)
      end
    end,
  }
end

---Fetch the changed files at a given commit
---@param rev Rev
---@param callback fun(files: FileEntry[]): nil
function PullRequest:get_commit_changed_files(rev, callback)
  local url = string.format("repos/%s/commits/%s", self.repo, rev.commit)
  gh.run {
    args = { "api", "--paginate", url, "--slurp" },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
      elseif output then
        local FileEntry = require("octo.reviews.file-entry").FileEntry
        local results = vim.json.decode(output)
        ---@type {
        ---  files: {
        ---    filename: string,
        ---    previous_filename: string,
        ---    patch: string,
        ---    status: string,
        ---    additions: integer,
        ---    deletions: integer,
        ---    changes: integer,
        ---  }[],
        ---}
        results = merge_pages(results)
        local files = {}
        if results.files then
          for _, result in ipairs(results.files) do
            local entry = FileEntry:new {
              path = result.filename,
              previous_path = result.previous_filename,
              patch = result.patch,
              pull_request = self,
              status = utils.file_status_map[result.status],
              stats = {
                additions = result.additions,
                deletions = result.deletions,
                changes = result.changes,
              },
            }
            table.insert(files, entry)
          end
          callback(files)
        end
      end
    end,
  }
end

return M
