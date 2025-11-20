---Handle parsing and building the URIs for octo buffers
---
--- This module provides utilities for working with Octo URI schemes that identify
--- GitHub resources (issues, pull requests, discussions, releases, and repositories).
---
--- URI Formats:
---   Without hostname (GitHub.com):
---     octo://owner/repo/issue/42
---     octo://owner/repo/pull/123
---     octo://owner/repo/discussion/5
---     octo://owner/repo/release/v1.0.0
---     octo://owner/repo/repo
---
---   With hostname (GitHub Enterprise):
---     octo://github.enterprise.com/owner/repo/issue/42
---     octo://github.enterprise.com/owner/repo/pull/123
---     octo://github.enterprise.com/owner/repo/discussion/5
---     octo://github.enterprise.com/owner/repo/release/v1.0.0
---     octo://github.enterprise.com/owner/repo/repo
---
---   Plural forms are normalized:
---     octo://owner/repo/issues/42  → kind = "issue"
---     octo://owner/repo/pulls/123  → kind = "pull"
---     octo://owner/repo/discussions/5 → kind = "discussion"
---
--- Release tags support alphanumeric characters, dots, hyphens, and underscores:
---   - v1.0.0
---   - v2.1.0-beta.1
---   - v1.0_RC-2
---
--- NOTE: This module uses lazy loading for utils to avoid circular dependencies.
--- DO NOT add 'require "octo.utils"' at the module level.

local notify = require "octo.notify"
local release = require "octo.release"

local M = {}

---@class BufferInfo
---@field repo string Full repository name (e.g., "owner/repo")
---@field kind string Resource type: "issue", "pull", "discussion", "release", or "repo"
---@field id string|nil Resource identifier (number for issues/PRs/discussions, tag for releases, "repo" for repositories)
---@field hostname string|nil GitHub Enterprise hostname (nil for github.com)

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
---@param _ any Unused parameter (for compatibility)
---@param repo string Repository in "owner/name" format
---@return string URI in format "octo://owner/name/repo"
---
--- Example:
---   get_repo_uri(nil, "pwntester/octo.nvim")
---   -- Returns: "octo://pwntester/octo.nvim/repo"
function M.get_repo_uri(_, repo)
  return string.format("octo://%s/repo", repo)
end

--- Get the URI for an issue
---@param ... string|number Issue number and optional repository
---@return string URI in format "octo://owner/name/issue/number"
---
--- Examples:
---   get_issue_uri(42)  -- Uses current git remote
---   get_issue_uri(42, "pwntester/octo.nvim")
---   -- Returns: "octo://pwntester/octo.nvim/issue/42"
function M.get_issue_uri(...)
  local repo, number = M.get_repo_number_from_varargs(...)
  return string.format("octo://%s/issue/%s", repo, number)
end

--- Get the URI for a pull request
---@param ... string|number PR number and optional repository
---@return string URI in format "octo://owner/name/pull/number"
---
--- Examples:
---   get_pull_request_uri(123)  -- Uses current git remote
---   get_pull_request_uri(123, "pwntester/octo.nvim")
---   -- Returns: "octo://pwntester/octo.nvim/pull/123"
function M.get_pull_request_uri(...)
  local repo, number = M.get_repo_number_from_varargs(...)
  return string.format("octo://%s/pull/%s", repo, number)
end

--- Get the URI for a discussion
---@param ... string|number Discussion number and optional repository
---@return string URI in format "octo://owner/name/discussion/number"
---
--- Examples:
---   get_discussion_uri(5)  -- Uses current git remote
---   get_discussion_uri(5, "pwntester/octo.nvim")
---   -- Returns: "octo://pwntester/octo.nvim/discussion/5"
function M.get_discussion_uri(...)
  local repo, number = M.get_repo_number_from_varargs(...)

  return string.format("octo://%s/discussion/%s", repo, number)
end

--- Get the URI for a release
---@param ... string|number Release tag name or ID, and optional repository
---@return string|nil URI in format "octo://owner/name/release/tag"
---
--- Examples:
---   get_release_uri("v1.0.0")  -- Uses current git remote
---   get_release_uri("v1.0.0", "pwntester/octo.nvim")
---   -- Returns: "octo://pwntester/octo.nvim/release/v1.0.0"
---
---   get_release_uri(12345678, "pwntester/octo.nvim")  -- Release ID
---   -- Fetches tag name from API, returns: "octo://pwntester/octo.nvim/release/v1.0.0"
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

--- Parse an Octo URI into its components
---@param bufname string URI to parse (e.g., "octo://owner/repo/issue/42")
---@return BufferInfo|nil Parsed components, or nil if URI is invalid
---
--- Examples:
---   parse("octo://pwntester/octo.nvim/issue/42")
---   -- Returns: { repo = "pwntester/octo.nvim", kind = "issue", id = "42" }
---
---   parse("octo://github.enterprise.com/pwntester/octo.nvim/pull/123")
---   -- Returns: { hostname = "github.enterprise.com", repo = "pwntester/octo.nvim", kind = "pull", id = "123" }
---
---   parse("octo://pwntester/octo.nvim/issues/42")  -- Plural normalized
---   -- Returns: { repo = "pwntester/octo.nvim", kind = "issue", id = "42" }
---
---   parse("octo://invalid")
---   -- Returns: nil
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
