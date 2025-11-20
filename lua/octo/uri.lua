---Handle parsing and building the URIs for octo buffers

local notify = require "octo.notify"
local release = require "octo.release"

local M = {}

---@class BufferInfo
---@field repo string
---@field kind string
---@field id string|nil
---@field hostname string|nil

--- Gets the repo and id from args.
---@type (fun(args: {n: integer}|string[], is_number: true): string?, integer?)|(fun(args: {n: integer}|string[], is_number: false): string?, string?)
local function get_repo_id_from_args(args, is_number)
  local repo, id ---@type string|nil, string|integer|nil
  if args.n == 0 then
    notify.error "Missing arguments"
    return
  elseif args.n == 1 then
    -- eg: Octo issue 1
    -- Lazy load utils to avoid circular dependency
    local utils = require "octo.utils"
    repo = utils.get_remote_name()
    id = tonumber(args[1])
  elseif args.n == 2 then
    -- eg: Octo issue 1 pwntester/octo.nvim
    repo = args[2] ---@type string
    id = is_number and tonumber(args[1]) or args[1]
  else
    notify.error "Unexpected arguments"
    return
  end
  if not repo then
    notify.error "Can not find repo name"
    return
  end
  if type(repo) ~= "string" then
    notify.error(("Expected repo name, received %s"):format(args[2]))
    return
  end
  if not id or (is_number and type(id) ~= "number") then
    notify.error(("Expected issue/PR number, received %s"):format(args[1]))
    return
  end
  return repo, id
end

--- Extracts repo and number from Octo command varargs
---@param ... string|number
---@return string? repo
---@return integer? number
function M.get_repo_number_from_varargs(...)
  local args = table.pack(...)
  return get_repo_id_from_args(args, true)
end

--- Get the URI for a repository
function M.get_repo_uri(_, repo)
  return string.format("octo://%s/repo", repo)
end

--- Get the URI for an issue
function M.get_issue_uri(...)
  local repo, number = M.get_repo_number_from_varargs(...)
  return string.format("octo://%s/issue/%s", repo, number)
end

--- Get the URI for an pull request
function M.get_pull_request_uri(...)
  local repo, number = M.get_repo_number_from_varargs(...)
  return string.format("octo://%s/pull/%s", repo, number)
end

function M.get_discussion_uri(...)
  local repo, number = M.get_repo_number_from_varargs(...)

  return string.format("octo://%s/discussion/%s", repo, number)
end

function M.get_release_uri(...)
  local args = table.pack(...)
  local repo, tag_name_or_id = get_repo_id_from_args(args, false)
  local release_id = tonumber(tag_name_or_id)
  if not release_id then
    return string.format("octo://%s/release/%s", repo, tag_name_or_id)
  end
  if not repo then
    notify.error "Cannot find repo name"
    return
  end
  -- Lazy load utils to avoid circular dependency
  local utils = require "octo.utils"
  local owner, name = utils.split_repo(repo)
  local tag_name = release.get_tag_from_release_id { owner = owner, repo = name, release_id = tostring(release_id) }
  return string.format("octo://%s/release/%s", repo, tag_name)
end

---@param bufname string
---@return BufferInfo|nil
M.parse = function(bufname)
  -- Try to parse with hostname: octo://hostname/owner/repo/kind/id
  local hostname, repo, kind, id = string.match(bufname, "octo://([^/]+)/([^/]+/[^/]+)/([^/]+)/([0-9a-zA-Z.%-_]+)")

  -- Fall back to without hostname: octo://owner/repo/kind/id
  if not hostname then
    repo, kind, id = string.match(bufname, "octo://(.+)/(.+)/([0-9a-zA-Z.%-_]+)")
    hostname = nil
  end

  -- Normalize plural forms to singular
  if kind == "issues" then
    kind = "issue"
  elseif kind == "pulls" then
    kind = "pull"
  elseif kind == "discussions" then
    kind = "discussion"
  end

  if id == "repo" or not repo then
    -- Try with hostname: octo://hostname/owner/repo/repo
    hostname, repo = string.match(bufname, "octo://([^/]+)/([^/]+/[^/]+)/repo")
    if not hostname then
      -- Fall back without hostname: octo://owner/repo/repo
      repo = string.match(bufname, "octo://(.+)/repo")
      hostname = nil
    end
    if repo then
      kind = "repo"
    end
  end

  if (kind == "issue" or kind == "pull") and not repo and not id then
    return
  elseif kind == "repo" and not repo then
    return
  end

  -- Return nil if we couldn't parse anything meaningful
  if not repo or not kind then
    return
  end

  return {
    repo = repo,
    kind = kind,
    id = id,
    hostname = hostname,
  }
end

return M
