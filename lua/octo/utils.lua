local config = require "octo.config"
local constants = require "octo.constants"
local gh = require "octo.gh"
local graphql = require "octo.gh.graphql"
local _, Job = pcall(require, "plenary.job")
local vim = vim

local M = {}

---@class OctoRepo
---@field host string
---@field name string?
---@field repo string?

local repo_id_cache = {}
local repo_templates_cache = {}
local repo_info_cache = {}
local path_sep = package.config:sub(1, 1)

M.viewed_state_map = {
  DISMISSED = { icon = "󰀨 ", hl = "OctoRed" },
  VIEWED = { icon = "󰗠 ", hl = "OctoGreen" },
  UNVIEWED = { icon = "󰄰 ", hl = "OctoBlue" },
}

M.state_msg_map = {
  APPROVED = "approved",
  CHANGES_REQUESTED = "requested changes",
  COMMENTED = "commented",
  DISMISSED = "dismissed",
  PENDING = "pending",
}

M.state_hl_map = {
  MERGED = "OctoStateMerged",
  CLOSED = "OctoStateClosed",
  DRAFT = "OctoStateDraft",
  COMPLETED = "OctoStateCompleted",
  NOT_PLANNED = "OctoStateNotPlanned",
  OPEN = "OctoStateOpen",
  APPROVED = "OctoStateApproved",
  CHANGES_REQUESTED = "OctoStateChangesRequested",
  COMMENTED = "OctoStateCommented",
  DISMISSED = "OctoStateDismissed",
  PENDING = "OctoStatePending",
  REVIEW_REQUIRED = "OctoStatePending",
  SUBMITTED = "OctoStateSubmitted",
}

M.state_icon_map = {
  MERGED = "⇌ ",
  CLOSED = "⚑ ",
  OPEN = "⚐ ",
  APPROVED = "✓ ",
  CHANGES_REQUESTED = "± ",
  COMMENTED = "☷ ",
  DISMISSED = " ",
  PENDING = " ",
  REVIEW_REQUIRED = " ",
}

M.state_message_map = {
  MERGED = "Merged",
  CLOSED = "Closed",
  OPEN = "Open",
  APPROVED = "Approved",
  CHANGES_REQUESTED = "Changes requested",
  COMMENTED = "Has review comments",
  DISMISSED = "Dismissed",
  PENDING = "Awaiting required review",
  REVIEW_REQUIRED = "Awaiting required review",
}

M.file_status_map = {
  modified = "M",
  added = "A",
  deleted = "D",
  renamed = "R",
}

-- https://docs.github.com/en/graphql/reference/enums#statusstate
M.state_map = {
  ERROR = { symbol = "× ", hl = "OctoStateDismissed" },
  FAILURE = { symbol = "× ", hl = "OctoStateDismissed" },
  EXPECTED = { symbol = " ", hl = "OctoStatePending" },
  PENDING = { symbol = " ", hl = "OctoStatePending" },
  SUCCESS = { symbol = "✓ ", hl = "OctoStateApproved" },
}

M.mergeable_hl_map = {
  CONFLICTING = "OctoStateDismissed",
  MERGEABLE = "OctoStateApproved",
  UNKNOWN = "OctoStatePending",
}

M.mergeable_message_map = {
  CONFLICTING = "× CONFLICTING",
  MERGEABLE = "✓ MERGEABLE",
  UNKNOWN = " PENDING",
}

M.merge_state_hl_map = {
  BEHIND = "OctoNormal",
  BLOCKED = "OctoStateDismissed",
  CLEAN = "OctoStateApproved",
  DIRTY = "OctoStateDismissed",
  DRAFT = "OctoStateDraftFloat",
  HAS_HOOKS = "OctoStateApproved",
  UNKNOWN = "OctoStatePending",
  UNSTABLE = "OctoStateDismissed",
}

M.merge_state_message_map = {
  BEHIND = "- OUT-OF-DATE",
  BLOCKED = "× BLOCKED",
  CLEAN = "✓ CLEAN",
  DIRTY = "× DIRTY",
  DRAFT = "= DRAFT",
  HAS_HOOKS = "✓ HAS-HOOKS",
  UNKNOWN = " PENDING",
  UNSTABLE = "! UNSTABLE",
}

M.auto_merge_method_map = {
  MERGE = "commit",
  REBASE = "rebase",
  SQUASH = "squash",
}

function M.trim(str)
  if type(vim.fn.trim) == "function" then
    return vim.fn.trim(str)
  elseif type(vim.trim) == "function" then
    return vim.trim(str)
  else
    return str:gsub("^%s*(.-)%s*$", "%1")
  end
end

function M.calculate_strongest_review_state(states)
  if vim.tbl_contains(states, "APPROVED") then
    return "APPROVED"
  elseif vim.tbl_contains(states, "CHANGES_REQUESTED") then
    return "CHANGES_REQUESTED"
  elseif vim.tbl_contains(states, "COMMENTED") then
    return "COMMENTED"
  elseif vim.tbl_contains(states, "PENDING") then
    return "PENDING"
  elseif vim.tbl_contains(states, "REVIEW_REQUIRED") then
    return "REVIEW_REQUIRED"
  end
end

M.reaction_map = {
  ["THUMBS_UP"] = "👍 ",
  ["THUMBS_DOWN"] = "👎 ",
  ["LAUGH"] = "😀 ",
  ["HOORAY"] = "🎉 ",
  ["CONFUSED"] = "😕 ",
  ["HEART"] = "❤️ ",
  ["ROCKET"] = "🚀 ",
  ["EYES"] = "👀 ",
}

---@param tbl unknown[]
---@param first integer
---@param last integer
---@param step integer?
---@return unknown[]
function M.tbl_slice(tbl, first, last, step)
  local sliced = {}
  for i = first or 1, last or #tbl, step or 1 do
    sliced[#sliced + 1] = tbl[i]
  end
  return sliced
end

function M.tbl_concat(a, b)
  local result = {}
  for i, v in ipairs(a) do
    result[i] = v
  end
  for i, v in ipairs(b) do
    result[#a + i] = v
  end

  return result
end

function table.pack(...)
  return { n = select("#", ...), ... }
end

function M.is_blank(s)
  return (
    s == nil
    or s == vim.NIL
    or (type(s) == "string" and string.match(s, "%S") == nil)
    or (type(s) == "table" and next(s) == nil)
  )
end

function M.parse_remote_url(url, aliases)
  -- filesystem path
  if vim.startswith(url, "/") or vim.startswith(url, ".") then
    return {
      host = nil,
      repo = url,
    }
  end
  -- remove trailing ".git"
  url = string.gsub(url, "%.git$", "")
  -- remove protocol scheme
  url = string.gsub(url, "^[^:]+://", "")
  -- remove user
  url = string.gsub(url, "^[^@]+@", "")
  -- if url contains two slashes
  local segments = vim.split(url, "/")
  local host, repo
  if #segments == 3 or (#segments == 4 and segments[4] == "") then
    host = segments[1]
    repo = segments[2] .. "/" .. segments[3]
  elseif #segments == 2 then
    local chunks = vim.split(url, ":")
    host = chunks[1]
    repo = chunks[#chunks]
  end

  for alias, rhost in pairs(aliases) do
    alias = alias:gsub("%-", "%%-")
    host = host:gsub("^" .. alias .. "$", rhost, 1)
  end
  if not M.is_blank(host) and not M.is_blank(repo) then
    return {
      host = host,
      repo = repo,
    }
  end
end

---Parse local git remotes from git cli
---@return OctoRepo[]
function M.parse_git_remote()
  local conf = config.values
  local aliases = conf.ssh_aliases
  local job = Job:new { command = "git", args = { "remote", "-v" }, cwd = vim.fn.getcwd() }
  job:sync()
  local stderr = table.concat(job:stderr_result(), "\n")
  if not M.is_blank(stderr) then
    return {}
  end
  local remotes = {}
  for _, line in ipairs(job:result()) do
    local name, url = line:match "^(%S+)%s+(%S+)"
    if name then
      local remote = M.parse_remote_url(url, aliases)
      if remote then
        remotes[name] = remote
      end
    end
  end
  return remotes
end

---Returns first host and repo information found in a list of remote values
---If no argument is provided, defaults to matching against config's default remote
---@param remote table | nil list of local remotes to match against
---@return OctoRepo
function M.get_remote(remote)
  local conf = config.values
  local remotes = M.parse_git_remote()
  for _, name in ipairs(remote or conf.default_remote) do
    if remotes[name] then
      return remotes[name]
    end
  end
  -- return github.com as default host
  return {
    host = "github.com",
    repo = nil,
  }
end

function M.get_remote_url()
  local host = M.get_remote_host()
  local remote_name = M.get_remote_name()
  if not host or not remote_name then
    M.error "No remote repository found"
    return
  end
  return "https://" .. host .. "/" .. remote_name
end

function M.get_all_remotes()
  return vim.tbl_values(M.parse_git_remote())
end

---@param remote table|nil
---@return string?
function M.get_remote_name(remote)
  return M.get_remote(remote).repo
end

function M.get_remote_host(remote)
  return M.get_remote(remote).host
end

function M.commit_exists(commit, cb)
  if not Job then
    return
  end
  Job:new({
    enable_recording = true,
    command = "git",
    args = { "cat-file", "-t", commit },
    on_exit = vim.schedule_wrap(function(j_self, _, _)
      if "commit" == M.trim(table.concat(j_self:result(), "\n")) then
        cb(true)
      else
        cb(false)
      end
    end),
  }):start()
end

---Add a milestone to an issue or PR
---@param issue boolean true if issue, false if PR
---@param number number issue or PR number
---@param milestone_name string milestone name
function M.add_milestone(issue, number, milestone_name)
  local command = issue and "issue" or "pr"
  local args = { command, "edit", number, "--milestone", milestone_name }

  gh.run {
    args = args,
    cb = function(output, stderr)
      if stderr and not M.is_blank(stderr) then
        M.error(stderr)
      elseif output then
        M.info("Added milestone " .. milestone_name)
      end
    end,
  }
end

---Remove a milestone from an issue or PR
---@param issue boolean true if issue, false if PR
---@param number number issue or PR number
function M.remove_milestone(issue, number)
  local command = issue and "issue" or "pr"
  local args = { command, "edit", number, "--remove-milestone" }

  gh.run {
    args = args,
    cb = function(output, stderr)
      if stderr and not M.is_blank(stderr) then
        M.error(stderr)
      elseif output then
        M.info "Removed milestone"
      end
    end,
  }
end

---https://docs.github.com/en/rest/issues/milestones?apiVersion=2022-11-28#create-a-milestone
---Create a new milestone
---@param title string
---@param description string
function M.create_milestone(title, description)
  if M.is_blank(title) then
    M.error "Title is required to create milestone"
    return
  end

  local owner, name = M.split_repo(M.get_remote_name())
  local endpoint = string.format("repos/%s/%s/milestones", owner, name)
  local args = { "api", "--method", "POST", endpoint }

  local data = {
    title = title,
    description = description,
    state = "open",
  }

  for key, value in pairs(data) do
    table.insert(args, "-f")
    table.insert(args, string.format("%s=%s", key, value))
  end

  gh.run {
    args = args,
    cb = function(output, stderr)
      if stderr and not M.is_blank(stderr) then
        M.error(stderr)
      elseif output then
        local resp = vim.json.decode(output)
        M.info("Created milestone " .. resp.title)
      end
    end,
  }
end

function M.develop_issue(issue_repo, issue_number, branch_repo)
  if M.is_blank(branch_repo) then
    branch_repo = M.get_remote_name()
  end

  local args = { "issue", "develop", "--repo", issue_repo, issue_number, "--checkout", "--branch-repo", branch_repo }

  gh.run {
    args = args,
    cb = function(stdout, stderr)
      if stderr and not M.is_blank(stderr) then
        M.error(stderr)
      elseif stdout then
        local output = vim.fn.system "git branch --show-current"
        M.info("Switched to " .. output)
      end
    end,
  }
end

function M.get_file_at_commit(path, commit, cb)
  if not Job then
    return
  end
  local job = Job:new {
    enable_recording = true,
    command = "git",
    args = { "show", string.format("%s:%s", commit, path) },
  }
  local result = job:sync()
  local output = table.concat(result, "\n")
  cb(vim.split(output, "\n"))
end

function M.in_pr_repo()
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer then
    M.error "Not in Octo buffer"
    return
  end
  if not buffer:isPullRequest() then
    M.error "Not in Octo PR buffer"
    return
  end

  local local_repo = M.get_remote_name()
  if buffer.node.baseRepository.nameWithOwner ~= local_repo then
    M.error(string.format("Not in PR repo. Expected %s, got %s", buffer.node.baseRepository.nameWithOwner, local_repo))
    return false
  else
    return true
  end
end

--- Determines if we are locally are in a branch matching the pr head ref
--- @param pr PullRequest
--- @return boolean
function M.in_pr_branch_locally_tracked(pr)
  local cmd = "git rev-parse --abbrev-ref --symbolic-full-name @{u}"
  local cmd_out = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    return false
  end

  local local_branch_with_local_remote = vim.split(string.gsub(cmd_out, "%s+", ""), "/")
  local local_remote = local_branch_with_local_remote[1]
  local local_branch = table.concat(local_branch_with_local_remote, "/", 2)

  -- Github repos are case insensitive, ignore case when comparing to local remotes
  local local_repo = M.get_remote_name({ local_remote }):lower()

  if local_repo == pr.head_repo:lower() and local_branch == pr.head_ref_name then
    return true
  end

  return false
end

-- the gh cli stores the remote info for a PR branch in a branch specific
-- config value.
--
-- this function searches for the upstream info, if it exists, for the current
-- checked out branch, within git config branch specific values.
--
-- if a config value is found the upstream branch name is returned, verbatim.
-- if no config value is found an empty string is returned.
--
-- this is useful when you want to determine if the currently checked out branch
-- maps to a PR HEAD, when 'gh pr checkout' is used.
function M.get_upstream_branch_from_config(pr)
  local branch_cmd = "git rev-parse --abbrev-ref HEAD"
  local branch = vim.fn.system(branch_cmd)
  if vim.v.shell_error ~= 0 then
    return ""
  end

  if #branch == 0 then
    return ""
  end

  -- trim white space off branch
  branch = string.gsub(branch, "%s+", "")

  local merge_config_cmd = string.format('git config --get-regexp "^branch\\.%s\\.merge"', branch)

  local merge_config = vim.fn.system(merge_config_cmd)
  if vim.v.shell_error ~= 0 then
    return ""
  end

  if #merge_config == 0 then
    return ""
  end

  -- split merge_config to key, value with space delimeter
  local merge_config_kv = vim.split(merge_config, "%s+")
  -- use > 2 since there maybe some garbage white space at the end of the map.
  if #merge_config_kv < 2 then
    return ""
  end

  local upstream_branch_ref = merge_config_kv[2]

  -- branch config can be in "refs/pull/{pr_number}/head" format
  if string.find(upstream_branch_ref, "^refs/pull/") then
    local pr_number = vim.split(upstream_branch_ref, "/")[3]
    -- tonumber handles any whitespace/quoting issues
    if tonumber(pr_number) == tonumber(pr.number) then
      return branch
    end
  else
    -- branch config can also be in "refs/heads/{upstream_branch_name} format"
    local upstream_branch_name = string.gsub(upstream_branch_ref, "^refs/heads/", "")
    return upstream_branch_name
  end

  return ""
end

-- Determines if we are locally in a branch matting the pr head ref when
-- the remote and branch information is stored in the branch's git config values
-- The gh CLI tool stores remote info directly in {branch.{branch}.x} configuration
-- fields and does not create a remote
function M.in_pr_branch_config_tracked(pr)
  return M.get_upstream_branch_from_config(pr):lower() == pr.head_ref_name
end

--- Determines if we are locally are in a branch matching the pr head ref
--- @param pr PullRequest
--- @return boolean
function M.in_pr_branch(pr)
  return M.in_pr_branch_locally_tracked(pr) or M.in_pr_branch_config_tracked(pr)
end

function M.checkout_pr(pr_number)
  gh.run {
    args = { "pr", "checkout", pr_number },
    cb = function(stdout, stderr)
      if stderr and not M.is_blank(stderr) then
        M.error(stderr)
      elseif stdout then
        local output = vim.fn.system "git branch --show-current"
        M.info("Switched to " .. output)
      end
    end,
  }
end

---@class CheckoutPrSyncOpts
---@field repo string
---@field pr_number number
---@field timeout number

---@param opts CheckoutPrSyncOpts
---@return nil
function M.checkout_pr_sync(opts)
  if not Job then
    return
  end
  Job:new({
    enable_recording = true,
    command = "gh",
    args = { "pr", "checkout", opts.pr_number, "--repo", opts.repo },
    on_exit = vim.schedule_wrap(function()
      local output = vim.fn.system "git branch --show-current"
      M.info("Switched to " .. output)
    end),
  }):sync(opts.timeout)
end

M.merge_method_to_flag = {
  squash = "--squash",
  rebase = "--rebase",
  commit = "--merge",
}

function M.insert_merge_flag(args, method)
  table.insert(args, M.merge_method_to_flag[method])
end

function M.insert_delete_flag(args, delete)
  if delete then
    table.insert(args, "--delete-branch")
  end
end

---Merges a PR by number
function M.merge_pr(pr_number)
  if not Job then
    M.error "Aborting PR merge"
    return
  end

  local conf = config.values
  local args = { "pr", "merge", pr_number }

  M.insert_merge_flag(args, conf.default_merge_method)
  M.insert_delete_flag(args, conf.default_delete_branch)

  Job:new({
    command = "gh",
    args = args,
    on_exit = vim.schedule_wrap(function(job, code)
      if code == 0 then
        M.info("Merged PR " .. pr_number .. "!")
      else
        local stderr = table.concat(job:stderr_result(), "\n")
        if not M.is_blank(stderr) then
          M.error(stderr)
        end
      end
    end),
  }):start()
end

---Formats a string as a date
function M.format_date(date_string)
  if date_string == nil then
    return ""
  end

  -- Parse the input date string (assumed to be in UTC)
  local year, month, day, hour, min, sec = date_string:match "(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)Z"
  local parsedTimeUTC = os.time {
    year = year,
    month = month,
    day = day,
    hour = hour,
    min = min,
    sec = sec,
    isdst = false, -- Input is in UTC
  }

  -- Get the offset of your local time zone from UTC
  local localTime = os.time()
  local utcTime = os.time(os.date "!*t")
  local timeZoneOffset = os.difftime(localTime, utcTime)

  -- Convert the parsed UTC time to local time
  local parsedTimeLocal = parsedTimeUTC + timeZoneOffset

  -- Calculate the time difference in seconds
  local diff = os.time() - parsedTimeLocal

  -- Determine if it's in the past or future
  local suffix = " ago"
  if diff < 0 then
    diff = -diff
    suffix = " from now"
  end

  -- Calculate time components
  local days = math.floor(diff / 86400)
  diff = diff % 86400
  local hours = math.floor(diff / 3600)
  diff = diff % 3600
  local minutes = math.floor(diff / 60)
  local seconds = diff % 60

  -- Check if the difference is more than 30 days
  if days > 30 then
    local dateOutput = os.date("*t", parsedTimeLocal)
    if dateOutput.year == os.date("*t", localTime).year then
      return os.date("%B %d", parsedTimeLocal) -- "Month Day"
    else
      return os.date("%Y %B %d", parsedTimeLocal) -- "Year Month Day"
    end
  end

  -- Return the human-readable format for differences within 30 days
  if days > 0 then
    return days .. " day" .. (days ~= 1 and "s" or "") .. suffix
  elseif hours > 0 then
    return hours .. " hour" .. (hours ~= 1 and "s" or "") .. suffix
  elseif minutes > 0 then
    return minutes .. " minute" .. (minutes ~= 1 and "s" or "") .. suffix
  else
    return seconds .. " second" .. (seconds ~= 1 and "s" or "") .. suffix
  end
end

---Gets repo internal GitHub ID
function M.get_repo_id(repo)
  if repo_id_cache[repo] then
    return repo_id_cache[repo]
  else
    local owner, name = M.split_repo(repo)
    local query = graphql("repository_id_query", owner, name)
    local output = gh.run {
      args = { "api", "graphql", "-f", string.format("query=%s", query) },
      mode = "sync",
    }
    local resp = vim.json.decode(output)
    local id = resp.data.repository.id
    repo_id_cache[repo] = id
    return id
  end
end

-- Checks if the current cwd is in a git repo
function M.cwd_is_git()
  local cmd = "git rev-parse --is-inside-work-tree"
  local out = vim.fn.system(cmd)
  out = out:gsub("%s+", "")
  return out == "true"
end

---Gets repo info
function M.get_repo_info(repo)
  if repo_info_cache[repo] then
    return repo_info_cache[repo]
  else
    local owner, name = M.split_repo(repo)
    local query = graphql("repository_query", owner, name)
    local output = gh.run {
      args = { "api", "graphql", "-f", string.format("query=%s", query) },
      mode = "sync",
    }
    local resp = vim.json.decode(output)
    local info = resp.data.repository
    repo_info_cache[repo] = info
    return info
  end
end

---Gets repo's templates
function M.get_repo_templates(repo)
  if repo_templates_cache[repo] then
    return repo_templates_cache[repo]
  else
    local owner, name = M.split_repo(repo)
    local query = graphql("repository_templates_query", owner, name)
    local output = gh.run {
      args = { "api", "graphql", "-f", string.format("query=%s", query) },
      mode = "sync",
    }
    local resp = vim.json.decode(output)
    local templates = resp.data.repository

    -- add an option to not use a template
    table.insert(templates.issueTemplates, {
      name = "DO NOT USE A TEMPLATE",
      about = "Create issue with no template",
      title = "",
      body = "",
    })

    repo_templates_cache[repo] = templates
    return templates
  end
end

---Helper method to aggregate an API paginated response
---@param text string
---@return table[]
function M.get_pages(text)
  local results = {}
  local page_outputs = vim.split(text, "\n")
  for _, page in ipairs(page_outputs) do
    local decoded_page = vim.json.decode(page)
    table.insert(results, decoded_page)
  end
  return results
end

--- Helper method to aggregate an API paginated response
function M.get_flatten_pages(text)
  local results = {}
  local page_outputs = vim.split(text, "\n")
  for _, page in ipairs(page_outputs) do
    local decoded_page = vim.json.decode(page)
    for _, result in ipairs(decoded_page) do
      table.insert(results, result)
    end
  end
  return results
end

--- Helper method to aggregate an API paginated response
---@param text string
---@param aggregation_key string
---@return table
function M.aggregate_pages(text, aggregation_key)
  -- aggregation key can be at any level (eg: comments)
  -- take the first response and extend it with elements from the
  -- subsequent responses
  local responses = M.get_pages(text)
  local base_resp = responses[1]
  if #responses > 1 then
    local base_page = M.get_nested_prop(base_resp, aggregation_key)
    for i = 2, #responses do
      local extra_page = M.get_nested_prop(responses[i], aggregation_key)
      vim.list_extend(base_page, extra_page)
    end
  end
  return base_resp
end

--- Helper method to aggregate an API paginated response
---@param obj table<string, unknown>
---@param prop string
---@return unknown
function M.get_nested_prop(obj, prop)
  local parts = vim.split(prop, "%.")
  if #parts == 1 then
    return obj[prop]
  else
    local part = parts[1]
    local remaining = table.concat(M.tbl_slice(parts, 2, #parts), ".")
    return M.get_nested_prop(obj[part], remaining)
  end
end

--- Escapes a characters on a string to be used as a JSON string
function M.escape_char(string)
  return string.gsub(string, "[\\]", {
    ["\\"] = "\\\\",
  })
end

--- Extracts repo and number from Octo command varargs
---@param ... string|number
---@return string? repo
---@return integer? number
function M.get_repo_number_from_varargs(...)
  local repo, number ---@type string|nil, integer|nil
  local args = table.pack(...)
  if args.n == 0 then
    M.error "Missing arguments"
    return
  elseif args.n == 1 then
    -- eg: Octo issue 1
    repo = M.get_remote_name()
    number = tonumber(args[1])
  elseif args.n == 2 then
    -- eg: Octo issue 1 pwntester/octo.nvim
    repo = args[2]
    number = tonumber(args[1])
  else
    M.error "Unexpected arguments"
    return
  end
  if not repo then
    M.error "Can not find repo name"
    return
  end
  if type(repo) ~= "string" then
    M.error(("Expected repo name, received %s"):format(args[2]))
    return
  end
  if not number or type(number) ~= "number" then
    M.error(("Expected issue/PR number, received %s"):format(args[1]))
    return
  end
  return repo, number
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

---Helper method opening octo buffers
function M.get(kind, ...)
  if kind == "issue" then
    M.get_issue(...)
  elseif kind == "pull_request" then
    M.get_pull_request(...)
  elseif kind == "discussion" then
    M.get_discussion(...)
  elseif kind == "repo" then
    M.get_repo(...)
  end
end

function M.get_repo(_, repo)
  vim.cmd("edit " .. M.get_repo_uri(_, repo))
end

function M.get_issue(...)
  vim.cmd("edit " .. M.get_issue_uri(...))
end

function M.get_pull_request(...)
  vim.cmd("edit " .. M.get_pull_request_uri(...))
end

function M.get_discussion(...)
  vim.cmd("edit " .. M.get_discussion_uri(...))
end

function M.parse_url(url)
  local repo, kind, number = string.match(url, constants.URL_ISSUE_PATTERN)
  if repo and number and kind == "issues" then
    return repo, number, "issue"
  elseif repo and number and kind == "pull" then
    return repo, number, kind
  end
end

--- Fetch file from GitHub repo at a given commit
---@param repo string
---@param commit string
---@param path string
---@param cb function
function M.get_file_contents(repo, commit, path, cb)
  local owner, name = M.split_repo(repo)
  local query = graphql("file_content_query", owner, name, commit, path)
  gh.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not M.is_blank(stderr) then
        M.error(stderr)
      elseif output then
        local resp = vim.json.decode(output)
        local blob = resp.data.repository.object
        local lines = {}
        if blob and blob ~= vim.NIL and type(blob.text) == "string" then
          lines = vim.split(blob.text, "\n")
        end
        cb(lines)
      end
    end,
  }
end

function M.set_timeout(delay, callback, ...)
  local timer = vim.loop.new_timer()
  local args = { ... }
  vim.loop.timer_start(timer, delay, 0, function()
    vim.loop.timer_stop(timer)
    vim.loop.close(timer)
    callback(unpack(args))
  end)
  return timer
end

function M.getwin4buf(bufnr)
  local tabpage = vim.api.nvim_get_current_tabpage()
  local wins = vim.api.nvim_tabpage_list_wins(tabpage)
  for _, w in ipairs(wins) do
    if bufnr == vim.api.nvim_win_get_buf(w) then
      return w
    end
  end
  return -1
end

function M.cursor_in_col_range(start_col, end_col)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local col = cursor[2] + 1
  if start_col and end_col then
    if start_col <= col and col <= end_col then
      return true
    end
  end
  return false
end

function M.split_repo(repo)
  local owner = vim.split(repo, "/")[1]
  local name = vim.split(repo, "/")[2]
  return owner, name
end

function M.extract_pattern_at_cursor(pattern, line, offset)
  line = line or vim.api.nvim_get_current_line()
  offset = offset or 0
  if offset > 0 and pattern:sub(1, 1) == "^" then
    return
  end
  local res = table.pack(line:find(pattern))
  if #res == 0 then
    return
  end
  local start_col = res[1]
  local end_col = res[2]
  if M.cursor_in_col_range(offset + start_col, offset + end_col) then
    return unpack(M.tbl_slice(res, 3, #res))
  elseif end_col == #line then
    return
  end
  return M.extract_pattern_at_cursor(pattern, line:sub(end_col + 1), offset + end_col)
end

function M.extract_issue_at_cursor(current_repo)
  local repo, number = M.extract_pattern_at_cursor(constants.LONG_ISSUE_PATTERN)
  if not repo or not number then
    number = M.extract_pattern_at_cursor(constants.SHORT_ISSUE_PATTERN)
    if number then
      repo = current_repo
    end
  end
  if not repo or not number then
    number = M.extract_pattern_at_cursor(constants.SHORT_ISSUE_LINE_BEGGINING_PATTERN)
    if number then
      repo = current_repo
    end
  end
  if not repo or not number then
    repo, _, number = M.extract_pattern_at_cursor(constants.URL_ISSUE_PATTERN)
  end
  return repo, number
end

function M.pattern_split(str, pattern)
  -- https://gist.github.com/boredom101/0074f1af6bd5cd6c7848ac6af3e88e85
  local words = {}
  for word in str:gmatch(pattern) do
    words[#words + 1] = word
  end
  return words
end

function M.text_wrap(text, width)
  -- https://gist.github.com/boredom101/0074f1af6bd5cd6c7848ac6af3e88e85

  width = width or math.floor((vim.fn.winwidth(0) * 3) / 4)
  local lines = M.pattern_split(text, "[^\r\n]+")
  local widthLeft
  local result = {}
  local line = {}

  -- Insert each source line into the result, one-by-one
  for k = 1, #lines do
    local sourceLine = lines[k]
    widthLeft = width -- all the width is left
    local words = M.pattern_split(sourceLine, "%S+")
    for l = 1, #words do
      local word = words[l]
      -- If the word is longer than an entire line:
      if #word > width then
        -- In case the word is longer than multible lines:
        while #word > width do
          -- Fit as much as possible
          table.insert(line, word:sub(0, widthLeft))
          table.insert(result, table.concat(line, " "))

          -- Take the rest of the word for next round
          word = word:sub(widthLeft + 1)
          widthLeft = width
          line = {}
        end

        -- The rest of the word that could share a line
        line = { word }
        widthLeft = width - (#word + 1)

        -- If we have no space left in the current line
      elseif (#word + 1) > widthLeft then
        table.insert(result, table.concat(line, " "))

        -- start next line
        line = { word }
        widthLeft = width - (#word + 1)

        -- if we could fit the word on the line
      else
        table.insert(line, word)
        widthLeft = widthLeft - (#word + 1)
      end
    end

    -- Insert the rest of the source line
    table.insert(result, table.concat(line, " "))
    line = {}
  end
  return result
end

function M.count_reactions(reaction_groups)
  local reactions_count = 0
  for _, group in ipairs(reaction_groups) do
    if group.users.totalCount > 0 then
      reactions_count = reactions_count + 1
    end
  end
  return reactions_count
end

function M.get_sorted_comment_lines(bufnr)
  local lines = {}
  local marks = vim.api.nvim_buf_get_extmarks(bufnr, constants.OCTO_COMMENT_NS, 0, -1, { details = true })
  for _, mark in ipairs(marks) do
    table.insert(lines, mark[2])
  end
  table.sort(lines)
  return lines
end

function M.is_thread_placed_in_buffer(thread, bufnr)
  local split, path = M.get_split_and_path(bufnr)
  if split == thread.diffSide and path == thread.path then
    return true
  end
  return false
end

function M.get_split_and_path(bufnr)
  local ok, props = pcall(vim.api.nvim_buf_get_var, bufnr, "octo_diff_props")
  if ok and props then
    return props.split, props.path
  end
end

function M.in_diff_window(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local ok, props = pcall(vim.api.nvim_buf_get_var, bufnr, "octo_diff_props")
  if ok and props then
    return true
  end
  return false
end

-- clear buffer undo history
function M.clear_history()
  if true then
    return
  end
  local old_undolevels = vim.o.undolevels
  vim.o.undolevels = -1
  vim.cmd [[exe "normal a \<BS>"]]
  vim.o.undolevels = old_undolevels
end

function M.clamp(value, min, max)
  if value < min then
    return min
  end
  if value > max then
    return max
  end
  return value
end

function M.enum(t)
  for i, v in ipairs(t) do
    t[v] = i
  end
  return t
end

function M.find_named_buffer(name)
  for _, v in ipairs(vim.api.nvim_list_bufs()) do
    if vim.fn.bufname(v) == name then
      return v
    end
  end
  return nil
end

function M.wipe_named_buffer(name)
  local bn = M.find_named_buffer(name)
  if bn then
    local win_ids = vim.fn.win_findbuf(bn)
    for _, id in ipairs(win_ids) do
      if vim.fn.win_gettype(id) ~= "autocmd" then
        vim.api.nvim_win_close(id, true)
      end
    end

    vim.api.nvim_buf_set_name(bn, "")
    vim.schedule(function()
      pcall(vim.api.nvim_buf_delete, bn, {})
    end)
  end
end

function M.str_shorten(s, new_length)
  if string.len(s) > new_length - 1 then
    return "…" .. s:sub(string.len(s) - new_length + 1, string.len(s))
  end
  return s
end

---Get a path relative to another path.
---@param path string
---@param relative_to string
---@return string
function M.path_relative(path, relative_to)
  local p, _ = path:gsub("^" .. M.path_to_matching_str(M.path_add_trailing(relative_to)), "")
  return p
end

function M.path_to_matching_str(path)
  return path:gsub("(%-)", "(%%-)"):gsub("(%.)", "(%%.)"):gsub("(%_)", "(%%_)")
end

function M.path_add_trailing(path)
  if path:sub(-1) == path_sep then
    return path
  end

  return path .. path_sep
end

---Get the path to the parent directory of the given path. Returns `nil` if the
---path has no parent.
---@param path string
---@param remove_trailing boolean
---@return string|nil
function M.path_parent(path, remove_trailing)
  path = " " .. M.path_remove_trailing(path)
  local i = path:match("^.+()" .. path_sep)
  if not i then
    return nil
  end
  path = path:sub(2, i)
  if remove_trailing then
    path = M.path_remove_trailing(path)
  end
  return path
end

function M.path_remove_trailing(path)
  local p, _ = path:gsub(path_sep .. "$", "")
  return p
end

---Get the basename of the given path.
---@param path string
---@return string
function M.path_basename(path)
  path = M.path_remove_trailing(path)
  local i = path:match("^.*()" .. path_sep)
  if not i then
    return path
  end
  return path:sub(i + 1, #path)
end

function M.path_extension(path)
  path = M.path_basename(path)
  return path:match ".*%.(.*)"
end

function M.path_join(paths)
  return table.concat(paths, path_sep)
end

--- Extract diffhunks from a diff file
function M.extract_diffhunks_from_diff(diff)
  local lines = vim.split(diff, "\n")
  local diffhunks = {}
  local current_diffhunk = {}
  local current_path
  local state
  for _, line in ipairs(lines) do
    if vim.startswith(line, "diff --git ") then
      if #current_diffhunk > 0 then
        diffhunks[current_path] = table.concat(current_diffhunk, "\n")
        current_diffhunk = {}
      end
      state = "diff"
    elseif vim.startswith(line, "index ") and state == "diff" then
      state = "index"
    elseif vim.startswith(line, "--- a/") and state == "index" then
      state = "fileA"
    elseif vim.startswith(line, "+++ b/") and state == "fileA" then
      current_path = string.sub(line, 7)
      state = "fileB"
    elseif vim.startswith(line, "@@") and state == "fileB" then
      state = "diffhunk"
      table.insert(current_diffhunk, line)
    elseif state == "diffhunk" then
      table.insert(current_diffhunk, line)
    end
  end
  return diffhunks
end

--- Calculate valid comment ranges
function M.process_patch(patch)
  -- @@ -from,no-of-lines in the file before  +from,no-of-lines in the file after @@
  -- The no-of-lines values may not be immediately obvious.
  -- The 'before' value is the sum of the 3 lead context lines, the number of - lines, and the 3 trailing context lines
  -- The 'after' values is the sum of 3 lead context lines, the number of + lines and the 3 trailing lines.
  -- In some cases there are additional intermediate context lines which are also added to those numbers.
  -- So the total number of lines displayed is commonly neither of the no-of-lines values!

  if not patch then
    return
  end
  local hunks = {}
  local left_ranges = {}
  local right_ranges = {}
  local hunk_strings = vim.split(patch:gsub("^@@", ""), "\n@@")
  for _, hunk in ipairs(hunk_strings) do
    local header = vim.split(hunk, "\n")[1]
    local found, _, left_start, left_length, right_start, right_length =
      string.find(header, "^%s*%-(%d+),(%d+)%s+%+(%d+),(%d+)%s*@@")
    if found then
      table.insert(hunks, hunk)
      table.insert(left_ranges, { tonumber(left_start), math.max(left_start + left_length - 1, 0) })
      table.insert(right_ranges, { tonumber(right_start), math.max(right_start + right_length - 1, 0) })
    else
      found, _, left_start, left_length, right_start = string.find(header, "^%s*%-(%d+),(%d+)%s+%+(%d+)%s*@@")
      if found then
        right_length = right_start + 1
        table.insert(hunks, hunk)
        table.insert(left_ranges, { tonumber(left_start), math.max(left_start + left_length - 1, 0) })
        table.insert(right_ranges, { tonumber(right_start), math.max(right_start + right_length - 1, 0) })
      end
    end
  end
  return hunks, left_ranges, right_ranges
end

-- calculate GutHub diffstat histogram bar
function M.diffstat(stats)
  -- round up to closest multiple of 5
  local total = stats.additions + stats.deletions
  if total == 0 then
    return {
      total = 0,
      additions = 0,
      deletions = 0,
      neutral = 5,
    }
  end
  local mod = total % 5
  local round = total - mod
  if mod > 0 then
    round = round + 5
  end
  -- calculate insertion to deletion ratio
  local unit = round / 5
  local additions = math.floor((0.5 + stats.additions) / unit)
  local deletions = math.floor((0.5 + stats.deletions) / unit)
  local neutral = 5 - additions - deletions
  return {
    total = total,
    additions = additions,
    deletions = deletions,
    neutral = neutral,
  }
end

function M.get_extmark_region(bufnr, mark)
  -- extmarks are placed on
  -- start line - 1 (except for line 0)
  -- end line + 2
  local start_line = mark[1] + 1
  if start_line == 1 then
    start_line = 0
  end
  local end_line = mark[3]["end_row"] - 2
  if start_line > end_line then
    end_line = start_line
  end
  -- Indexing is zero-based, end-exclusive, so adding 1 to end line
  local status, lines = pcall(vim.api.nvim_buf_get_lines, bufnr, start_line, end_line + 1, true)
  if status and lines then
    local text = vim.fn.join(lines, "\n")
    return start_line, end_line, text
  end
end

function M.fork_repo()
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]

  if not buffer or not buffer:isRepo() then
    return
  end
  M.info(string.format("Cloning %s. It can take a few minutes", buffer.repo))
  M.info(vim.fn.system('echo "n" | gh repo fork ' .. buffer.repo .. " 2>&1 | cat "))
end

function M.notify(msg, level)
  if level == 1 then
    level = vim.log.levels.INFO
  elseif level == 2 then
    level = vim.log.levels.ERROR
  else
    level = vim.log.levels.INFO
  end
  vim.notify(msg, level, { title = "Octo.nvim" })
end

function M.info(msg)
  vim.notify(msg, vim.log.levels.INFO, { title = "Octo.nvim" })
end

function M.error(msg)
  vim.notify(msg, vim.log.levels.ERROR, { title = "Octo.nvim" })
end

function M.get_pull_request_for_current_branch(cb)
  gh.run {
    args = { "pr", "view", "--json", "id,number,headRepositoryOwner,headRepository,isCrossRepository,url" },
    cb = function(out)
      if out == "" then
        M.error "No pr found for current branch"
        return
      end
      local pr = vim.json.decode(out)
      local base_owner
      local base_name
      if pr.number then
        if pr.isCrossRepository then
          -- Parsing the pr url is the only way to get the target repo owner if the pr is cross repo
          if not pr.url then
            M.error "Failed to get pr url"
            return
          end
          local url_suffix = pr.url:match "[^/]+/[^/]+/pull/%d+$"
          if not url_suffix then
            M.error "Failed to parse pr url"
            return
          end
          local iter = url_suffix:gmatch "[^/]+/"
          base_owner = iter():sub(1, -2)
          base_name = iter():sub(1, -2)
        else
          base_owner = pr.headRepositoryOwner.login
          base_name = pr.headRepository.name
        end
        local number = pr.number
        local id = pr.id
        local query = graphql("pull_request_query", base_owner, base_name, number, _G.octo_pv2_fragment)
        gh.run {
          args = { "api", "graphql", "--paginate", "--jq", ".", "-f", string.format("query=%s", query) },
          cb = function(output, stderr)
            if stderr and not M.is_blank(stderr) then
              vim.api.nvim_err_writeln(stderr)
            elseif output then
              local resp = M.aggregate_pages(output, "data.repository.pullRequest.timelineItems.nodes")
              local obj = resp.data.repository.pullRequest
              local Rev = require("octo.reviews.rev").Rev
              local PullRequest = require("octo.model.pull-request").PullRequest
              local pull_request = PullRequest:new {
                repo = base_owner .. "/" .. base_name,
                head_repo = obj.headRepository.nameWithOwner,
                number = number,
                id = id,
                head_ref_name = obj.headRefName,
                left = Rev:new(obj.baseRefOid),
                right = Rev:new(obj.headRefOid),
                files = obj.files.nodes,
              }
              cb(pull_request)
            end
          end,
        }
      end
    end,
  }
end

local function close_preview_window(winnr, bufnrs)
  vim.schedule(function()
    -- exit if we are in one of ignored buffers
    if bufnrs and vim.tbl_contains(bufnrs, vim.api.nvim_get_current_buf()) then
      return
    end

    local augroup = "preview_window_" .. winnr
    pcall(vim.api.nvim_del_augroup_by_name, augroup)
    pcall(vim.api.nvim_win_close, winnr, true)
  end)
end

--- Creates autocommands to close a preview window when events happen.
---
---@param events table list of events
---@param winnr number window id of preview window
---@param bufnrs table list of buffers where the preview window will remain visible
---@see autocmd-events
function M.close_preview_autocmd(events, winnr, bufnrs)
  local augroup = vim.api.nvim_create_augroup("preview_window_" .. winnr, {
    clear = true,
  })

  -- close the preview window when entered a buffer that is not
  -- the floating window buffer or the buffer that spawned it
  vim.api.nvim_create_autocmd("BufEnter", {
    group = augroup,
    callback = function()
      close_preview_window(winnr, bufnrs)
    end,
  })

  if #events > 0 then
    vim.api.nvim_create_autocmd(events, {
      buffer = bufnrs[2],
      callback = function()
        close_preview_window(winnr)
      end,
    })
  end
end

function M.get_user_id(login)
  local query = graphql("user_query", login)
  local output = gh.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    mode = "sync",
  }
  if output then
    local resp = vim.json.decode(output)
    if resp.data.user and resp.data.user ~= vim.NIL then
      return resp.data.user.id
    end
  end
end

function M.get_label_id(label)
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer then
    M.error "Not in Octo buffer"
    return
  end

  local owner, name = M.split_repo(buffer.repo)
  local query = graphql("repo_labels_query", owner, name)
  local output = gh.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    mode = "sync",
  }
  if output then
    local resp = vim.json.decode(output)
    if resp.data.repository.labels.nodes and resp.data.repository.labels.nodes ~= vim.NIL then
      for _, l in ipairs(resp.data.repository.labels.nodes) do
        if l.name == label then
          return l.id
        end
      end
    end
  end
end

--- Generate maps from diffhunk line to code line:
function M.generate_position2line_map(diffhunk)
  local diffhunk_lines = vim.split(diffhunk, "\n")
  local diff_directive = diffhunk_lines[1]
  local left_offset, right_offset = string.match(diff_directive, "@@%s*%-(%d+),%d+%s%+(%d+)")
  local right_side_lines = {}
  local left_side_lines = {}
  local right_side_line = right_offset
  local left_side_line = left_offset
  for i = 2, #diffhunk_lines do
    local line = diffhunk_lines[i]
    if vim.startswith(line, "+") then
      right_side_lines[i] = right_side_line
      right_side_line = right_side_line + 1
    elseif vim.startswith(line, "-") then
      left_side_lines[i] = left_side_line
      left_side_line = left_side_line + 1
    elseif not vim.startswith(line, "-") and not vim.startswith(line, "+") then
      right_side_lines[i] = right_side_line
      left_side_lines[i] = left_side_line
      right_side_line = right_side_line + 1
      left_side_line = left_side_line + 1
    end
  end
  if left_offset == nil then
    left_offset = 0
  end
  if right_offset == nil then
    right_offset = 0
  end
  return {
    left_side_lines = left_side_lines,
    right_side_lines = right_side_lines,
    right_offset = right_offset,
    left_offset = left_offset,
  }
end

--- Generates map from buffer line to diffhunk position
function M.generate_line2position_map(diffhunk)
  local map = M.generate_position2line_map(diffhunk)
  local left_side_lines, right_side_lines = {}, {}
  for k, v in pairs(map.left_side_lines) do
    left_side_lines[tostring(v)] = k
  end
  for k, v in pairs(map.right_side_lines) do
    right_side_lines[tostring(v)] = k
  end
  return {
    left_side_lines = left_side_lines,
    right_side_lines = right_side_lines,
    right_offset = map.right_offset,
    left_offset = map.left_offset,
  }
end

--- Extract REST Id from comment
function M.extract_rest_id(comment_url)
  if M.is_blank(comment_url) then
    return
  end
  local rest_id = ""
  local sep = "_r"
  for i in string.gmatch(comment_url, "([^" .. sep .. "]+)") do
    rest_id = i
  end
  return rest_id
end

--- Apply mappings to a buffer
---@param kind string
---@param bufnr integer
function M.apply_mappings(kind, bufnr)
  local mappings = require "octo.mappings"
  local conf = config.values
  for action, value in pairs(conf.mappings[kind]) do
    if
      not M.is_blank(value)
      and not M.is_blank(action)
      and not M.is_blank(value.lhs)
      and not M.is_blank(mappings[action])
    then
      if M.is_blank(value.desc) then
        value.desc = ""
      end
      local mapping_opts = { silent = true, noremap = true, buffer = bufnr, desc = value.desc }
      local mode = value.mode or "n"
      vim.keymap.set(mode, value.lhs, mappings[action], mapping_opts)
    end
  end
end

-- Returns the starting and ending lines to be commented based on the calling context.
function M.get_lines_from_context(calling_context)
  local line_number_start = nil
  local line_number_end = nil
  if calling_context == "line" then
    line_number_start = vim.fn.line "."
    line_number_end = line_number_start
  elseif calling_context == "visual" then
    line_number_start = vim.fn.line "v"
    line_number_end = vim.fn.line "."
  elseif calling_context == "motion" then
    line_number_start = vim.fn.getpos("'[")[2]
    line_number_end = vim.fn.getpos("']")[2]
  end
  return line_number_start, line_number_end
end

function M.convert_vim_mapping_to_fzf(vim_mapping)
  local fzf_mapping = string.gsub(vim_mapping, "<[cC]%-(.*)>", "ctrl-%1")
  fzf_mapping = string.gsub(fzf_mapping, "<[amAM]%-(.*)>", "alt-%1")
  return string.lower(fzf_mapping)
end

--- Logic to determine the state displayed for issue or PR
---@param isIssue boolean
---@param state string
---@param stateReason string | nil
---@return string
function M.get_displayed_state(isIssue, state, stateReason, isDraft)
  if isIssue and state == "CLOSED" then
    return stateReason or state
  end

  if isDraft then
    return "DRAFT"
  end

  return state
end

--- @class EntryObject
--- @field state string
--- @field isDraft boolean
--- @field stateReason string
--- @field isAnswered boolean
--- @field closed boolean

--- @class Entry
--- @field kind string
--- @field obj EntryObject

--- @class Icon
--- @field [1] string The icon
--- @field [2] string|nil The highlight group for the icon
--- @see octo.ui.colors for the available highlight groups

-- Symbols found with "Telescope symbols"
M.icons = {
  issue = {
    open = { " ", "OctoGreen" },
    closed = { " ", "OctoPurple" },
    not_planned = { " ", "OctoGrey" },
  },
  pull_request = {
    open = { " ", "OctoGreen" },
    draft = { " ", "OctoGrey" },
    merged = { " ", "OctoPurple" },
    closed = { " ", "OctoRed" },
  },
  discussion = {
    open = { " ", "OctoGrey" },
    answered = { " ", "OctoGreen" },
    closed = { " ", "OctoRed" },
  },
  notification = {
    issue = {
      unread = { " ", "OctoBlue" },
      read = { " ", "OctoGrey" },
    },
    pull_request = {
      unread = { " ", "OctoBlue" },
      read = { " ", "OctoGrey" },
    },
  },
  unknown = { " " },
}

--- Get the icon for the entry
---@param entry Entry: The entry to get the icon for
---@return Icon: The icon for the entry
function M.get_icon(entry)
  local kind = entry.kind

  if kind == "issue" then
    local state = entry.obj.state
    local stateReason = entry.obj.stateReason

    if state == "OPEN" then
      return M.icons.issue.open
    elseif state == "CLOSED" and stateReason == "NOT_PLANNED" then
      return M.icons.issue.not_planned
    elseif state == "CLOSED" then
      return M.icons.issue.closed
    end
  elseif kind == "pull_request" then
    local state = entry.obj.state
    local isDraft = entry.obj.isDraft

    if state == "MERGED" then
      return M.icons.pull_request.merged
    elseif state == "CLOSED" then
      return M.icons.pull_request.closed
    elseif isDraft then
      return M.icons.pull_request.draft
    elseif state == "OPEN" then
      return M.icons.pull_request.open
    end
  elseif kind == "discussion" then
    local closed = entry.obj.closed
    local isAnswered = entry.obj.isAnswered

    if isAnswered ~= vim.NIL and isAnswered then
      return M.icons.discussion.answered
    elseif not closed then
      return M.icons.discussion.open
    else
      return M.icons.discussion.closed
    end
  end

  return M.icons.unknown
end

return M
