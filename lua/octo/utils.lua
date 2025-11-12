local config = require "octo.config"
local constants = require "octo.constants"
local gh = require "octo.gh"
local graphql = require "octo.gh.graphql"
local queries = require "octo.gh.queries"
local _, Job = pcall(require, "plenary.job")
local release = require "octo.release"
local notify = require "octo.notify"
local vim = vim

local M = {}

---@class OctoRepo
---@field host string
---@field name string?
---@field repo string?

local repo_id_cache = {} ---@type table<string, string>
local repo_templates_cache = {} ---@type table<string, octo.queries.RepositoryTemplates.data.repository>
local repo_info_cache = {} ---@type table<string, octo.Repository>
local path_sep = package.config:sub(1, 1)

M.viewed_state_map = {
  DISMISSED = { icon = "󰀨 ", hl = "OctoRed" },
  VIEWED = { icon = "󰗠 ", hl = "OctoGreen" },
  UNVIEWED = { icon = "󰄰 ", hl = "OctoBlue" },
}

---@type table<DeploymentState, table<string, string>>
M.deployed_state_map = {
  ABANDONED = { "Abandoned", "OctoBubbleRed" },
  ACTIVE = { "Active", "OctoBubbleGreen" },
  DESTROYED = { "Destroyed", "OctoBubbleGray" },
  ERROR = { "Error", "OctoBubbleRed" },
  FAILURE = { "Failure", "OctoBubbleRed" },
  INACTIVE = { "Inactive", "OctoBubbleGrey" },
  IN_PROGRESS = { "In Progress", "OctoBubbleYellow" },
  PENDING = { "Pending", "OctoBubbleYellow" },
  QUEUED = { "Queued", "OctoBubbleYellow" },
  SUCCESS = { "Success", "OctoBubbleGreen" },
  WAITING = { "Waiting", "OctoBubbleYellow" },
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
  removed = "D",
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
  MERGE = "merge",
  REBASE = "rebase",
  SQUASH = "squash",
}

---@param str string
function M.trim(str)
  if type(vim.fn.trim) == "function" then
    return vim.fn.trim(str)
  elseif type(vim.trim) == "function" then
    return vim.trim(str)
  else
    return str:gsub("^%s*(.-)%s*$", "%1")
  end
end

---@param states string[]
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
  ["LAUGH"] = "😄 ",
  ["HOORAY"] = "🎉 ",
  ["CONFUSED"] = "😕 ",
  ["HEART"] = "❤️ ",
  ["ROCKET"] = "🚀 ",
  ["EYES"] = "👀 ",
}

---@generic TItem
---@param tbl TItem[]
---@param first integer
---@param last integer
---@param step integer?
---@return TItem[]
function M.tbl_slice(tbl, first, last, step)
  local sliced = {} ---@type any[]
  for i = first or 1, last or #tbl, step or 1 do
    sliced[#sliced + 1] = tbl[i]
  end
  return sliced
end

---@diagnostic disable-next-line: duplicate-set-field
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

---@param url string
---@param aliases table<string, string>
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
  ---@type string, string
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
    ---@type string
    host = host:gsub("^" .. alias .. "$", rhost, 1)
  end
  if not M.is_blank(host) and not M.is_blank(repo) then
    ---@type OctoRepo
    return {
      host = host,
      repo = repo,
    }
  end
end

---Parse local git remotes from git cli
function M.parse_git_remote()
  local conf = config.values
  local aliases = conf.ssh_aliases
  ---@diagnostic disable-next-line: missing-fields
  local job = Job:new { command = "git", args = { "remote", "-v" }, cwd = vim.fn.getcwd() }
  job:sync()
  local stderr = table.concat(job:stderr_result(), "\n")
  if not M.is_blank(stderr) then
    return {}
  end
  ---@type table<string, OctoRepo>
  local remotes = {}
  for _, line in
    ipairs(job:result() --[[@as string[] ]])
  do
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
---@param remote string[] | nil list of local remotes to match against
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

---@param commit string
---@param cb fun(exists: boolean)
function M.commit_exists(commit, cb)
  if not Job then
    return
  end
  ---@diagnostic disable-next-line: missing-fields
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

  gh[command].edit {
    number,
    milestone = milestone_name,
    opts = {
      cb = gh.create_callback {
        success = function(_)
          M.info("Added milestone " .. milestone_name)
        end,
      },
    },
  }
end

---Remove a milestone from an issue or PR
---@param issue boolean true if issue, false if PR
---@param number number issue or PR number
function M.remove_milestone(issue, number)
  local command = issue and "issue" or "pr"

  gh[command].edit {
    number,
    remove_milestone = true,
    opts = {
      cb = gh.create_callback {
        success = function(_)
          M.info "Removed milestone"
        end,
      },
    },
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

  local owner, name = M.split_repo(M.get_remote_name() --[[@as string]])
  local endpoint = string.format("repos/%s/%s/milestones", owner, name)

  gh.api.post {
    endpoint,
    f = {
      title = title,
      description = description,
      state = "open",
    },
    opts = {
      cb = gh.create_callback {
        success = function(_)
          M.info("Created milestone " .. title)
        end,
      },
    },
  }
end

local function branch_switch_message()
  local output = vim.fn.system "git branch --show-current"
  M.info("Switched to " .. vim.fn.trim(output))
end

function M.develop_issue(issue_repo, issue_number, branch_repo)
  if M.is_blank(branch_repo) then
    branch_repo = M.get_remote_name()
  end

  gh.issue.develop {
    issue_number,
    repo = issue_repo,
    checkout = true,
    branch_repo = branch_repo,
    opts = {
      cb = gh.create_callback {
        success = branch_switch_message,
      },
    },
  }
end

---@param path string
---@param commit string
---@param cb fun(lines: string[])
function M.get_file_at_commit(path, commit, cb)
  if not Job then
    return
  end
  ---@diagnostic disable-next-line: missing-fields
  local job = Job:new {
    enable_recording = true,
    command = "git",
    args = { "show", string.format("%s:%s", commit, path) },
  }
  ---@type string[]?
  local result = job:sync()
  if not result then
    M.error "Failed to get file contents"
    return
  end
  local output = table.concat(result, "\n")
  cb(vim.split(output, "\n"))
end

function M.in_pr_repo()
  local buffer = M.get_current_buffer()
  if not buffer then
    M.error "Not in Octo buffer"
    return
  end
  if not buffer:isPullRequest() then
    M.error "Not in Octo PR buffer"
    return
  end

  local local_repo = M.get_remote_name()
  if buffer:pullRequest().baseRepository.nameWithOwner ~= local_repo then
    M.error(
      string.format(
        "Not in PR repo. Expected %s, got %s",
        buffer:pullRequest().baseRepository.nameWithOwner,
        local_repo
      )
    )
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
---@param pr PullRequest
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

  -- split merge_config to key, value with space delimiter
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
---@param pr PullRequest
function M.in_pr_branch_config_tracked(pr)
  return M.get_upstream_branch_from_config(pr):lower() == pr.head_ref_name
end

--- Determines if we are locally are in a branch matching the pr head ref
--- @param pr PullRequest
--- @return boolean
function M.in_pr_branch(pr)
  return M.in_pr_branch_locally_tracked(pr) or M.in_pr_branch_config_tracked(pr)
end

---@param pr_number integer
function M.checkout_pr(pr_number)
  gh.pr.checkout {
    pr_number,
    opts = {
      cb = gh.create_callback {
        success = branch_switch_message,
      },
    },
  }
end

---@class CheckoutPrSyncOpts
---@field repo string
---@field pr_number number

---@param opts CheckoutPrSyncOpts
---@return nil
function M.checkout_pr_sync(opts)
  gh.pr.checkout {
    opts.pr_number,
    repo = opts.repo,
    opts = {
      mode = "sync",
    },
  }
  branch_switch_message()
end

M.merge_queue_to_flag = {
  queue = "--queue",
  auto = "--auto",
}

M.merge_method_to_flag = {
  squash = "--squash",
  rebase = "--rebase",
  merge = "--merge",
}

---@param args string[]
---@param method string
function M.insert_merge_flag(args, method)
  table.insert(args, M.merge_method_to_flag[method])
end

---@param args string[]
---@param delete boolean
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

  ---@diagnostic disable-next-line: missing-fields
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

--- Formats a integer a large integer by taking the most significant digits with a suffix.
--- e.g. 123456789 -> 12.3m
---@param n integer
---@param is_capitalized boolean
function M.format_large_int(n, is_capitalized)
  if n < 1000 then
    return tostring(n)
  end
  local suffixes = is_capitalized and { "K", "M", "B", "T" } or { "k", "m", "b", "t" }
  local i = 0
  while n >= 1000 do
    i = i + 1
    n = n / 1000
  end
  return string.format("%.1f%s", n, suffixes[i])
end

---Formats number of seconds as a duration string
---@param seconds integer
---@return string
function M.format_seconds(seconds)
  if seconds < 60 then
    return seconds .. "s"
  end
  local minutes = math.floor(seconds / 60)
  seconds = seconds % 60
  if minutes < 60 then
    return string.format("%dm%ds", minutes, seconds)
  end
  local hours = math.floor(minutes / 60)
  minutes = minutes % 60
  if hours < 24 then
    return string.format("%dh%dm", hours, minutes)
  end
  local days = math.floor(hours / 24)
  hours = hours % 24
  return string.format("%dd%dh", days, hours)
end

---Formats a string as a date
---@param date_string string ISO 8601 date string in UTC format
---@return integer time in seconds since epoch
function M.parse_utc_date(date_string)
  -- Parse the input date string (assumed to be in UTC)
  local year, month, day, hour, min, sec = date_string:match "(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)Z"
  return os.time {
    year = year,
    month = month,
    day = day,
    hour = hour,
    min = min,
    sec = sec,
    isdst = false, -- Input is in UTC
  }
end

---Relative date options
---@class DateOpts
---@field minutes? integer
---@field hours? integer
---@field days? integer
---@field weeks? integer

---@param opts DateOpts
---@param reference? string|osdate|number Optional reference date (ISO string or os.time() or os.date table)
function M.relative_date(opts, reference)
  ---@type integer
  local ref_ts
  if type(reference) == "string" then
    ref_ts = M.parse_utc_date(reference)
  elseif type(reference) == "table" then
    ref_ts = os.time(reference)
  elseif type(reference) == "number" then
    ref_ts = reference
  else
    ref_ts = os.time()
  end

  local delta = (opts.minutes or 0) * 60
    + (opts.hours or 0) * 3600
    + (opts.days or 0) * 86400
    + (opts.weeks or 0) * 604800
  local new_ts = ref_ts - delta

  return os.date("!%Y-%m-%dT%H:%M:%SZ", new_ts)
end

---@param start_date string
---@param end_date string
---@return integer number of seconds between the two dates
function M.seconds_between(start_date, end_date)
  return os.difftime(M.parse_utc_date(end_date), M.parse_utc_date(start_date))
end

---Formats a string as a date
---@param date_string string
---@param round_under_one_minute? boolean defaults to true
---@return string
function M.format_date(date_string, round_under_one_minute)
  if date_string == nil then
    return ""
  end

  round_under_one_minute = round_under_one_minute == nil and true or round_under_one_minute

  local parsedTimeUTC = M.parse_utc_date(date_string)

  -- Get the offset of your local time zone from UTC
  local localTime = os.time()
  local utcTime = os.time(os.date "!*t" --[[@as osdateparam]])
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
      -- "Month Day"
      return os.date("%B %d", parsedTimeLocal) --[[@as string]]
    else
      -- "Year Month Day"
      return os.date("%Y %B %d", parsedTimeLocal) --[[@as string]]
    end
  end

  -- Return the human-readable format for differences within 30 days
  if days > 0 then
    return days .. " day" .. (days ~= 1 and "s" or "") .. suffix
  elseif hours > 0 then
    return hours .. " hour" .. (hours ~= 1 and "s" or "") .. suffix
  elseif minutes > 0 then
    return minutes .. " minute" .. (minutes ~= 1 and "s" or "") .. suffix
  elseif round_under_one_minute then
    return "now"
  else
    return seconds .. " second" .. (seconds ~= 1 and "s" or "") .. suffix
  end
end

---Gets repo internal GitHub ID
---@param repo string
function M.get_repo_id(repo)
  if repo_id_cache[repo] then
    return repo_id_cache[repo]
  end

  local owner, name = M.split_repo(repo)
  local id = gh.api.graphql {
    query = queries.repository_id,
    fields = { owner = owner, name = name },
    jq = ".data.repository.id",
    opts = { mode = "sync" },
  }
  repo_id_cache[repo] = id
  return id
end

-- Checks if the current cwd is in a git repo
function M.cwd_is_git()
  local cmd = "git rev-parse --is-inside-work-tree"
  local out = vim.fn.system(cmd)
  out = out:gsub("%s+", "")
  return out == "true"
end

---Gets repo info
---@param repo string
function M.get_repo_info(repo)
  if repo_info_cache[repo] then
    return repo_info_cache[repo]
  end

  local owner, name = M.split_repo(repo)
  local output = gh.api.graphql {
    query = queries.repository,
    fields = { owner = owner, name = name },
    jq = ".data.repository",
    opts = { mode = "sync" },
  }
  if not output then
    M.error "Failed to get repo info"
    return
  end
  ---@type octo.Repository
  local info = vim.json.decode(output)
  repo_info_cache[repo] = info
  return info
end

---Gets repo's templates
---@param repo string
function M.get_repo_templates(repo)
  if repo_templates_cache[repo] then
    return repo_templates_cache[repo]
  end

  local owner, name = M.split_repo(repo)
  local output = gh.api.graphql {
    query = queries.repository_templates,
    fields = { owner = owner, name = name },
    jq = ".data.repository",
    opts = { mode = "sync" },
  }
  if not output then
    M.error "Failed to get repo templates"
    return
  end
  ---@type octo.queries.RepositoryTemplates.data.repository
  local templates = vim.json.decode(output)

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

---@param text string
---@param cb fun(results: any[], page: any): nil
function M.callback_per_page(text, cb)
  local results = {}
  local page_output = vim.split(text, "\n")
  for _, page in ipairs(page_output) do
    local decoded_page = vim.json.decode(page)
    cb(results, decoded_page)
  end
  return results
end

---Helper method to aggregate an API paginated response
---@param text string
---@return table[]
function M.get_pages(text)
  return M.callback_per_page(text, table.insert)
end

---Helper method to aggregate an API paginated response
---@param text string
function M.get_flatten_pages(text)
  return M.callback_per_page(text, vim.list_extend)
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
    ---@type any
    local base_page = M.get_nested_prop(base_resp, aggregation_key)
    for i = 2, #responses do
      ---@type any
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

---Escapes a characters on a string to be used as a JSON string
---@param s string
---@return string
function M.escape_char(s)
  local escaped = string.gsub(s, "[\\]", {
    ["\\"] = "\\\\",
  })
  return escaped
end

--- Gets the repo and id from args.
---@type (fun(args: {n: integer}|string[], is_number: true): string?, integer?)|(fun(args: {n: integer}|string[], is_number: false): string?, string?)
local function get_repo_id_from_args(args, is_number)
  local repo, id ---@type string|nil, string|integer|nil
  if args.n == 0 then
    M.error "Missing arguments"
    return
  elseif args.n == 1 then
    -- eg: Octo issue 1
    repo = M.get_remote_name()
    id = tonumber(args[1])
  elseif args.n == 2 then
    -- eg: Octo issue 1 pwntester/octo.nvim
    repo = args[2] ---@type string
    id = is_number and tonumber(args[1]) or args[1]
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
  if not id or (is_number and type(id) ~= "number") then
    M.error(("Expected issue/PR number, received %s"):format(args[1]))
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
    M.error "Cannot find repo name"
    return
  end
  local owner, name = M.split_repo(repo)
  local tag_name = release.get_tag_from_release_id { owner = owner, repo = name, release_id = tostring(release_id) }
  return string.format("octo://%s/release/%s", repo, tag_name)
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
  elseif kind == "release" then
    M.get_release(...)
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

function M.get_release(...)
  vim.cmd("edit " .. M.get_release_uri(...))
end

---@param url string
---@return string?, string?, string?
function M.parse_url(url)
  local repo, kind, number = string.match(url, constants.URL_ISSUE_PATTERN)
  if repo and number and kind == "issues" then
    return repo, number, "issue"
  elseif repo and number and kind == "pull" then
    return repo, number, kind
  elseif repo and number and kind == "discussions" then
    return repo, number, "discussion"
  elseif not repo then
    repo, kind, number = string.match(url, constants.URL_RELEASE_PATTERN)
    if repo and number and kind == "releases" then
      return repo, number, "release"
    end
  end
end

--- Fetch file from GitHub repo at a given commit
---@param repo string
---@param commit string
---@param path string
---@param cb fun(lines: string[]): nil
function M.get_file_contents(repo, commit, path, cb)
  local owner, name = M.split_repo(repo)
  gh.api.graphql {
    query = queries.file_content,
    f = { owner = owner, name = name, expression = commit .. ":" .. path },
    jq = ".data.repository.object.text",
    opts = {
      cb = gh.create_callback {
        success = function(blob)
          local lines = {}
          if blob then
            lines = vim.split(blob, "\n")
          end
          cb(lines)
        end,
      },
    },
  }
end

---@generic TParams
---@param delay integer
---@param callback fun(...: TParams)
---@param ... TParams
function M.set_timeout(delay, callback, ...)
  local timer = vim.uv.new_timer()
  if not timer then
    M.error "Failed to create timer"
    return
  end
  local args = { ... }
  vim.uv.timer_start(timer, delay, 0, function()
    vim.uv.timer_stop(timer)
    vim.uv.close(timer)
    callback(unpack(args))
  end)
  return timer
end

---@param bufnr integer
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

---@param start_col integer
---@param end_col integer
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

---@param repo string
function M.split_repo(repo)
  local owner = vim.split(repo, "/")[1]
  local name = vim.split(repo, "/")[2]
  return owner, name
end

---@param pattern string
---@param line? string
---@param offset? integer
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
  ---@type integer
  local start_col = res[1]
  ---@type integer
  local end_col = res[2]
  if M.cursor_in_col_range(offset + start_col, offset + end_col) then
    return unpack(M.tbl_slice(res, 3, #res))
  elseif end_col == #line then
    return
  end
  return M.extract_pattern_at_cursor(pattern, line:sub(end_col + 1), offset + end_col)
end

---@param current_repo string
function M.extract_issue_at_cursor(current_repo)
  ---@type string?, integer?
  local repo, number = M.extract_pattern_at_cursor(constants.LONG_ISSUE_PATTERN)
  if not repo or not number then
    number = M.extract_pattern_at_cursor(constants.SHORT_ISSUE_PATTERN)
    if number then
      repo = current_repo
    end
  end
  if not repo or not number then
    number = M.extract_pattern_at_cursor(constants.SHORT_ISSUE_LINE_BEGINNING_PATTERN)
    if number then
      repo = current_repo
    end
  end
  if not repo or not number then
    repo, _, number = M.extract_pattern_at_cursor(constants.URL_ISSUE_PATTERN)
  end
  return repo, number
end

---@param str string
---@param pattern string
function M.pattern_split(str, pattern)
  -- https://gist.github.com/boredom101/0074f1af6bd5cd6c7848ac6af3e88e85
  local words = {} ---@type string[]
  for word in str:gmatch(pattern) do
    words[#words + 1] = word
  end
  return words
end

---@param text string
---@param width integer
function M.text_wrap(text, width)
  -- https://gist.github.com/boredom101/0074f1af6bd5cd6c7848ac6af3e88e85

  width = width or math.floor((vim.fn.winwidth(0) * 3) / 4)
  local lines = M.pattern_split(text, "[^\r\n]+")
  local widthLeft ---@type integer
  local result = {} ---@type string[]
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
        -- In case the word is longer than multiple lines:
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

---@param reaction_groups octo.ReactionGroupsFragment.reactionGroups[]
function M.count_reactions(reaction_groups)
  local reactions_count = 0
  for _, group in ipairs(reaction_groups) do
    if group.users.totalCount > 0 then
      reactions_count = reactions_count + 1
    end
  end
  return reactions_count
end

---@param bufnr integer
function M.get_sorted_comment_lines(bufnr)
  local lines = {} ---@type integer[]
  local marks = vim.api.nvim_buf_get_extmarks(bufnr, constants.OCTO_COMMENT_NS, 0, -1, { details = true })
  for _, mark in ipairs(marks) do
    table.insert(lines, mark[2])
  end
  table.sort(lines)
  return lines
end

---@param bufnr integer
function M.is_thread_placed_in_buffer(thread, bufnr)
  local split, path = M.get_split_and_path(bufnr)
  if split == thread.diffSide and path == thread.path then
    return true
  end
  return false
end

---@param bufnr integer
---@return string?, string?
function M.get_split_and_path(bufnr)
  local ok, props = pcall(vim.api.nvim_buf_get_var, bufnr, "octo_diff_props")
  if ok and props then
    return props.split, props.path
  end
end

---@param bufnr integer
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
  ---@type integer
  local old_undolevels = vim.o.undolevels
  vim.o.undolevels = -1
  vim.cmd [[exe "normal a \<BS>"]]
  vim.o.undolevels = old_undolevels
end

---@param value number
---@param min number
---@param max number
function M.clamp(value, min, max)
  if value < min then
    return min
  end
  if value > max then
    return max
  end
  return value
end

---@param name string
function M.find_named_buffer(name)
  for _, v in ipairs(vim.api.nvim_list_bufs()) do
    if vim.fn.bufname(v) == name then
      return v
    end
  end
  return nil
end

---@param name string
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

---@param s string
---@param new_length integer
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

---@param path string
function M.path_to_matching_str(path)
  return path:gsub("(%-)", "(%%-)"):gsub("(%.)", "(%%.)"):gsub("(%_)", "(%%_)")
end

---@param path string
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

---@param path string
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

---@param path string
---@return string?
function M.path_extension(path)
  path = M.path_basename(path)
  return path:match ".*%.(.*)"
end

---@param paths string[]
function M.path_join(paths)
  return table.concat(paths, path_sep)
end

---Extract diffhunks from a diff file
---@param diff string
function M.extract_diffhunks_from_diff(diff)
  local lines = vim.split(diff, "\n")
  local diffhunks = {} ---@type table<string, string>
  local current_diffhunk = {}
  local current_path ---@type string
  local state ---@type string
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

---Calculate valid comment ranges
---@param patch string?
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
  local hunks = {} ---@type string[]
  local left_ranges = {} ---@type [integer, integer][]
  local right_ranges = {} ---@type [integer, integer][]
  local hunk_strings = vim.split(patch:gsub("^@@", ""), "\n@@")
  for _, hunk in ipairs(hunk_strings) do
    local header = vim.split(hunk, "\n")[1]
    ---@type integer?, integer?, integer, integer, integer, integer
    local found, _, left_start, left_length, right_start, right_length =
      string.find(header, "^%s*%-(%d+),(%d+)%s+%+(%d+),(%d+)%s*@@")
    if found then
      table.insert(hunks, hunk)
      table.insert(left_ranges, { tonumber(left_start), math.max(left_start + left_length - 1, 0) })
      table.insert(right_ranges, { tonumber(right_start), math.max(right_start + right_length - 1, 0) })
    else
      ---@type integer?, integer?, integer, integer, integer
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

---calculate GitHub diffstat histogram bar
---@param stats { additions: integer, deletions: integer }
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

---@param bufnr integer
---@param mark vim.api.keyset.get_extmark_item_by_id
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
  local buffer = M.get_current_buffer()

  if not buffer or not buffer:isRepo() then
    return
  end
  M.info(string.format("Cloning %s. It can take a few minutes", buffer.repo))
  M.info(vim.fn.system('echo "n" | gh repo fork ' .. buffer.repo .. " 2>&1 | cat "))
end

---For backward compatibility
M.notify = notify.notify
M.info = notify.info
M.error = notify.error

---@param cb fun(pr: PullRequest):nil
function M.get_pull_request_for_current_branch(cb)
  gh.run {
    args = { "pr", "view", "--json", "id,number,headRepositoryOwner,headRepository,isCrossRepository,url" },
    cb = function(out)
      if out == "" then
        M.error "No pr found for current branch"
        return
      end
      ---@class octo.PullRequestViewJson
      ---@field id string
      ---@field number integer
      ---@field headRepositoryOwner { login: string, name: string }
      ---@field headRepository { name: string }
      ---@field isCrossRepository boolean
      ---@field url string

      ---@type octo.PullRequestViewJson
      local pr = vim.json.decode(out)
      local base_owner ---@type string
      local base_name ---@type string
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
          ---@type fun(): string
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
              M.print_err(stderr)
            elseif output then
              local resp = M.aggregate_pages(output, "data.repository.pullRequest.timelineItems.nodes")
              ---@type octo.PullRequest
              local obj = resp.data.repository.pullRequest
              local PullRequest = require "octo.model.pull-request"

              local opts = {
                repo = base_owner .. "/" .. base_name,
                head_repo = obj.headRepository.nameWithOwner,
                number = number,
                id = id,
                head_ref_name = obj.headRefName,
              }

              PullRequest.create_with_merge_base(opts, obj, cb)
            end
          end,
        }
      end
    end,
  }
end

---@param winnr integer
---@param bufnrs? integer[]
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
---@param events string[] list of events
---@param winnr integer window id of preview window
---@param bufnrs integer[] list of buffers where the preview window will remain visible
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

---@param login string
function M.get_user_id(login)
  local id = gh.api.graphql {
    query = queries.user,
    fields = { login = login },
    jq = ".data.user.id",
    opts = { mode = "sync" },
  }

  if id == "" then
    return
  end

  return id --[[@as string]]
end

---@param label string
function M.get_label_id(label)
  local buffer = M.get_current_buffer()
  if not buffer then
    M.error "Not in Octo buffer"
    return
  end

  local owner, name = M.split_repo(buffer.repo)
  local jq = ([[
    .data.repository.labels.nodes
    | map(select(.name == "{label}"))
    | .[0].id
  ]]):gsub("{label}", label)
  local id = gh.api.graphql {
    query = queries.repo_labels,
    fields = { owner = owner, name = name },
    jq = jq,
    opts = { mode = "sync" },
  }
  if id == "" then
    return
  end

  return id
end

--- Generate maps from diffhunk line to code line:
---@param diffhunk string
function M.generate_position2line_map(diffhunk)
  local diffhunk_lines = vim.split(diffhunk, "\n")
  local diff_directive = diffhunk_lines[1]
  ---@type integer, integer
  local left_offset, right_offset = string.match(diff_directive, "@@%s*%-(%d+),%d+%s%+(%d+)")
  local right_side_lines = {} ---@type table<integer, integer>
  local left_side_lines = {} ---@type table<integer, integer>
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
  ---@type { left_side_lines: table<integer, integer>, right_side_lines: table<integer, integer>, right_offset: integer, left_offset: integer }
  return {
    left_side_lines = left_side_lines,
    right_side_lines = right_side_lines,
    right_offset = right_offset,
    left_offset = left_offset,
  }
end

---Generates map from buffer line to diffhunk position
---@param diffhunk string
function M.generate_line2position_map(diffhunk)
  local map = M.generate_position2line_map(diffhunk)
  ---@type table<string, integer>, table<string, integer>
  local left_side_lines, right_side_lines = {}, {}
  for k, v in pairs(map.left_side_lines) do
    left_side_lines[tostring(v)] = k
  end
  for k, v in pairs(map.right_side_lines) do
    right_side_lines[tostring(v)] = k
  end
  ---@type { left_side_lines: table<string, integer>, right_side_lines: table<string, integer>, right_offset: integer, left_offset: integer }
  return {
    left_side_lines = left_side_lines,
    right_side_lines = right_side_lines,
    right_offset = map.right_offset,
    left_offset = map.left_offset,
  }
end

---Extract REST Id from comment
---@param comment_url string
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

---Returns the starting and ending lines to be commented based on the calling context.
---@param calling_context "line" | "visual" | "motion"
---@return integer|nil, integer|nil
function M.get_lines_from_context(calling_context)
  ---@type integer|nil
  local line_number_start = nil
  ---@type integer|nil
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
  -- Ensure line_number_start is always <= line_number_end
  if line_number_start and line_number_end and line_number_start > line_number_end then
    local temp = line_number_start
    line_number_start = line_number_end
    line_number_end = temp
  end
  return line_number_start, line_number_end
end

---@param vim_mapping string
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
    discussion = {
      unread = { " ", "OctoBlue" },
      read = { " ", "OctoGrey" },
    },
    release = {
      unread = { " ", "OctoBlue" },
      read = { " ", "OctoGrey" },
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

---@param url string
---@param register? string
function M.copy_url(url, register)
  register = register or "+"
  vim.fn.setreg(register, url, "c")
  local message = register ~= "+" and "(" .. register .. " register)" or "to the system clipboard (+ register)"
  M.info("Copied '" .. url .. "' " .. message)
end

---@param sha string
---@param register? string
function M.copy_sha(sha, register)
  register = register or "+"
  vim.fn.setreg(register, sha, "c")
  local message = register ~= "+" and "(" .. register .. " register)" or "to the system clipboard (+ register)"
  M.info("Copied SHA '" .. sha:sub(1, 7) .. "' " .. message)
end

---@param opts { prompt: string }
function M.input(opts)
  vim.fn.inputsave()
  local value = vim.fn.input(opts)
  vim.fn.inputrestore()

  return value
end

---@return OctoBuffer?
function M.get_current_buffer()
  local bufnr = vim.api.nvim_get_current_buf()
  return octo_buffers[bufnr]
end

---@param discussion octo.Discussion
function M.count_discussion_replies(discussion)
  local total_replies = 0
  for _, comment in ipairs(discussion.comments.nodes) do
    total_replies = total_replies + comment.replies.totalCount
  end

  return total_replies
end

---@param msg string
function M.print_err(msg)
  vim.api.nvim_echo({ { msg } }, true, { err = true })
end

---@param tbl table<any, any>
---@param key any
---@return any
function M.pop_key(tbl, key)
  local value = tbl[key]
  tbl[key] = nil
  return value
end

---Insert text under the current cursor position
---@param text string
---@return nil
function M.put_text_under_cursor(text)
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  vim.api.nvim_buf_set_lines(bufnr, cursor_pos[1], cursor_pos[1], false, vim.split(text, "\n"))
end

---@param data table
---@return string
local get_content_by_priority = function(data)
  local priority = { "root", "docs", "github" }
  for _, loc in ipairs(priority) do
    if not M.is_blank(data[loc]) and not M.is_blank(data[loc].text) then
      return data[loc].text
    end
  end
  return ""
end

---@param repo string Full name of repository
M.display_contributing_file = function(repo)
  local owner, name = M.split_repo(repo)
  gh.api.graphql {
    query = queries.contributing_file,
    F = { owner = owner, name = name },
    jq = ".data.repository",
    opts = {
      cb = gh.create_callback {
        success = function(data)
          data = vim.json.decode(data)
          local content = get_content_by_priority(data)

          if M.is_blank(content) then
            M.error("No CONTRIBUTING.md found for " .. repo)
            return
          end

          local _, bufnr = require("octo.ui.window").create_centered_float {
            header = "CONTRIBUTING.md",
            content = vim.split(content, "\n"),
          }

          vim.bo[bufnr].filetype = "markdown"
          vim.bo[bufnr].modifiable = false
          vim.bo[bufnr].readonly = true
        end,
      },
    },
  }
end

---Populate the Octo search command with options
---@param opts { include_current_repo: boolean, query: string? }
function M.create_base_search_command(opts)
  local cmd = ":Octo search "
  if opts.include_current_repo then
    local repo = M.get_remote_name()
    if repo ~= nil then
      cmd = cmd .. "repo:" .. repo .. " "
    else
      M.error "No remote found"
    end
  end
  if opts.query then
    cmd = cmd .. opts.query
  end

  vim.fn.feedkeys(vim.api.nvim_replace_termcodes(cmd, true, true, true), "n")
end

---@param str string
---@return string
function M.title_case(str)
  return (str:gsub("(%a)([%w_'.]*)", function(first, rest)
    return first:upper() .. rest:lower()
  end))
end

---@param str string
---@return string
function M.remove_underscore(str)
  return (str:gsub("_", " "))
end

return M
