local gh = require "octo.gh"
local queries = require "octo.gh.queries"
local utils = require "octo.utils"

local M = {}

local get_branches = function(repoWithOwner)
  local opts = {
    "/repos/{owner}/{repo}/branches",
    jq = "map(.name)",
    opts = { mode = "sync" },
  }
  if not utils.is_blank(repoWithOwner) then
    local owner, repo = utils.split_repo(repoWithOwner)
    opts.format = { owner = owner, repo = repo }
  end
  local output = gh.api.get(opts)

  if utils.is_blank(output) then
    utils.error "No branches found"
    return {}
  end

  return vim.json.decode(output)
end

local get_labels = function(search, repo)
  local opts = {
    json = "name",
    jq = "map(.name)",
    opts = { mode = "sync" },
  }
  if search then
    opts.search = search
  end

  if repo then
    opts.repo = repo
  end

  local output = gh.label.list(opts)
  if utils.is_blank(output) then
    utils.error "No labels found"
    return {}
  end

  return vim.json.decode(output)
end

local get_milestones = function(repoWithOwner)
  if utils.is_blank(repoWithOwner) then
    repoWithOwner = utils.get_remote_name()
  end

  local owner, name = utils.split_repo(repoWithOwner)

  local output = gh.api.graphql {
    query = queries.open_milestones,
    fields = { owner = owner, name = name, n_milestones = 10 },
    jq = ".data.repository.milestones.nodes | map(.title)",
    opts = { mode = "sync" },
  }

  local milestones = vim.json.decode(output)

  if #milestones == 0 then
    utils.error("No milestones found for " .. repoWithOwner)
  end

  return milestones
end

local get_valid = function(name, valid, argLead)
  local desired = string.gsub(argLead, name .. ":", "")
  local valid_types = {}
  for _, type in ipairs(valid) do
    if string.match(type, " ") then
      type = '"' .. type .. '"'
    end

    if string.match(type, desired) then
      table.insert(valid_types, name .. ":" .. type)
    end
  end
  return valid_types
end

M.complete = function(argLead, cmdLine, cursorPos)
  if not string.match(argLead, ":") then
    local possible = {
      "repo",
      "is",
      "state",
      "reason",
      "type",
      "label",
      "milestone",
      "project",
      "head",
      "status",
      "base",
      "in",
      "no",
      "author",
      "assignee",
      "reviewer",
      "language",
      "mentions",
      "team",
      "commenter",
      "comments",
      "interactions",
      "reactions",
      "draft",
      "review",
      "reviewed-by",
      "review-requested",
      "user-review-requested",
      "team-review-requested",
      "created",
      "updated",
      "closed",
      "archived",
      "involves",
      "linked",
      --- Discussions
      "org",
      "answered-by",
      "category",
    }

    local valid = {}
    for _, p in ipairs(possible) do
      if string.match(p, argLead) then
        table.insert(valid, p .. ":")
      end
    end
    return valid
  end

  if vim.startswith(argLead, "head") then
    local repo = string.match(cmdLine, "repo:([%w%-%./_]+)")

    local branches = get_branches(repo)
    local valid_branches = {}
    for _, branch in ipairs(branches) do
      if string.match(branch, " ") then
        branch = '"' .. branch .. '"'
      end

      table.insert(valid_branches, "head:" .. branch)
    end
    return valid_branches
  end

  if vim.startswith(argLead, "base") then
    local repo = string.match(cmdLine, "repo:([%w%-%./_]+)")

    local desired_branch = string.gsub(argLead, "base:", "")
    local branches = get_branches(repo)
    local valid_branches = {}
    for _, branch in ipairs(branches) do
      if string.match(branch, " ") then
        branch = '"' .. branch .. '"'
      end

      if string.match(branch, desired_branch) then
        table.insert(valid_branches, "base:" .. branch)
      end
    end
    return valid_branches
  end

  if vim.startswith(argLead, "state") then
    local states = {
      "open",
      "closed",
    }
    return get_valid("state", states, argLead)
  end

  if vim.startswith(argLead, "reason") then
    local reasons = {
      "completed",
      "not planned",
    }
    return get_valid("reason", reasons, argLead)
  end

  if vim.startswith(argLead, "milestone") then
    local repo = string.match(cmdLine, "repo:([%w%-%./_]+)")

    local desired_milestone = string.gsub(argLead, "milestone:", "")
    local milestones = get_milestones(repo)
    local valid_milestones = {}
    for _, milestone in ipairs(milestones) do
      if string.match(milestone, " ") then
        milestone = '"' .. milestone .. '"'
      end

      if string.match(milestone, desired_milestone) then
        table.insert(valid_milestones, "milestone:" .. milestone)
      end
    end
    return valid_milestones
  end

  if vim.startswith(argLead, "type") then
    local types = {
      "Bug",
      "Task",
      "Feature",
      "issue",
      "pr",
    }
    return get_valid("type", types, argLead)
  end

  if vim.startswith(argLead, "label") then
    local repo = string.match(cmdLine, "repo:([%w%-%./_]+)")

    local desired_label = string.gsub(argLead, "label:", "")
    local labels = get_labels(desired_label, repo)
    local valid_labels = {}
    for _, label in ipairs(labels) do
      if string.match(label, " ") then
        label = '"' .. label .. '"'
      end

      table.insert(valid_labels, "label:" .. label)
    end
    return valid_labels
  end

  if vim.startswith(argLead, "in") then
    local types = {
      "title",
      "body",
      "comments",
    }
    return get_valid("in", types, argLead)
  end

  if vim.startswith(argLead, "no") then
    return get_valid("no", {
      "label",
      "milestone",
      "assignee",
      "project",
    }, argLead)
  end

  if vim.startswith(argLead, "is") then
    local types = {
      "pr",
      "issue",
      "discussion",
    }
    local states = {
      "merged",
      "open",
      "closed",
      "draft",
      "public",
      "private",
      "locked",
      "unlocked",
      "archived",
      "unarchived",
      "queued",
      -- Discussions
      "answered",
      "unanswered",
    }
    local combined = {}
    for _, type in ipairs(types) do
      table.insert(combined, type)
    end
    for _, state in ipairs(states) do
      table.insert(combined, state)
    end

    return get_valid("is", combined, argLead)
  end

  return {}
end

return M
