--- Completions while using the search command
--- https://docs.github.com/en/search-github/searching-on-github
--- See https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/filtering-and-searching-issues-and-pull-requests
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

local get_repos = function(owner, name)
  local query = name .. " owner:" .. owner

  local output = gh.api.graphql {
    query = queries.search,
    fields = { prompt = query, type = "REPOSITORY" },
    jq = ".data.search.nodes | map(.name)",
    opts = { mode = "sync" },
  }
  return vim.json.decode(output)
end

local get_users = function(prompt)
  local output = gh.api.graphql {
    query = queries.search,
    f = { prompt = prompt, type = "USER" },
    jq = ".data.search.nodes | map(.login)",
    opts = { mode = "sync" },
  }
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

local get_categories = function(repoWithOwner)
  if utils.is_blank(repoWithOwner) then
    repoWithOwner = utils.get_remote_name()
  end

  local owner, name = utils.split_repo(repoWithOwner)

  local output = gh.api.graphql {
    query = queries.discussion_categories,
    fields = { owner = owner, name = name },
    jq = ".data.repository.discussionCategories.nodes | map(.name)",
    opts = { mode = "sync" },
  }

  local categories = vim.json.decode(output)

  if #categories == 0 then
    utils.error("No categories found for " .. repoWithOwner)
  end

  return categories
end

local get_closest_valid = function(name, valid, argLead)
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

local remove_through_colon = function(qualifier, value)
  local pattern = ":"
  local start_index = string.find(value, pattern)
  if start_index then
    return string.sub(value, start_index + #pattern)
  end
  return value
end

local create_complete_user = function(qualifier)
  return function(argLead, cmdLine)
    local partial_user = remove_through_colon(qualifier, argLead)
    local users = get_users(partial_user)
    local valid_users = {}

    for _, user in ipairs(users) do
      if not utils.is_blank(user) then
        table.insert(valid_users, qualifier .. ":" .. user)
      end
    end
    return valid_users
  end
end

local complete_repo = function(argLead, cmdLine)
  local repoWithName = string.match(cmdLine, "repo:([%w%-%./_]+)")
  if utils.is_blank(repoWithName) then
    return {}
  end

  local owner, repo = utils.split_repo(repoWithName)

  local has_slash = string.match(argLead, "/")

  if not has_slash then
    local users = get_users(owner)
    local valid_users = {}

    for _, user in ipairs(users) do
      if not utils.is_blank(user) then
        table.insert(valid_users, "repo:" .. user .. "/")
      end
    end
    return valid_users
  end

  local repos = get_repos(owner, repo)
  local valid_repos = {}
  for _, repo in ipairs(repos) do
    if string.match(repo, " ") then
      repo = '"' .. repo .. '"'
    end

    table.insert(valid_repos, "repo:" .. owner .. "/" .. repo)
  end
  return valid_repos
end

local create_complete_branch = function(qualifier)
  return function(argLead, cmdLine)
    if vim.startswith(argLead, qualifier) then
      local repo = string.match(cmdLine, "repo:([%w%-%./_]+)")

      local desired_branch = string.gsub(argLead, qualifier .. ":", "")
      local branches = get_branches(repo)
      local valid_branches = {}
      for _, branch in ipairs(branches) do
        if string.match(branch, " ") then
          branch = '"' .. branch .. '"'
        end

        if string.match(branch, desired_branch) then
          table.insert(valid_branches, qualifier .. ":" .. branch)
        end
      end
      return valid_branches
    end
  end
end

local complete_milestone = function(argLead, cmdLine)
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

local complete_category = function(argLead, cmdLine)
  local repo = string.match(cmdLine, "repo:([%w%-%./_]+)")

  local desired_category = string.gsub(argLead, "category:", "")
  local categories = get_categories(repo)
  local valid_categories = {}
  for _, category in ipairs(categories) do
    if string.match(category, " ") then
      category = '"' .. category .. '"'
    end

    if string.match(category, desired_category) then
      table.insert(valid_categories, "category:" .. category)
    end
  end
  return valid_categories
end

local complete_label = function(argLead, cmdLine)
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

local qualifiers = {
  repo = complete_repo,
  is = {
    "pr",
    "issue",
    "discussion",
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
    "answered",
    "unanswered",
  },
  state = { "open", "closed" },
  reason = { "completed", "not planned" },
  type = { "Bug", "Task", "Feature", "issue", "pr" },
  label = complete_label,
  milestone = complete_milestone,
  "project",
  head = create_complete_branch "head",
  base = create_complete_branch "base",
  status = { "pending", "success", "failure" },
  ["in"] = { "title", "body", "comments" },
  no = { "label", "milestone", "assignee", "project" },
  --- User related
  author = create_complete_user "author",
  assignee = create_complete_user "assignee",
  reviewer = create_complete_user "reviewer",
  commenter = create_complete_user "commenter",
  ["reviewed-by"] = create_complete_user "reviewed-by",
  involves = create_complete_user "involves",
  mentions = create_complete_user "mentions",
  "language",
  "team",
  "comments",
  "interactions",
  "reactions",
  draft = { "true", "false" },
  "review",
  "review-requested",
  "user-review-requested",
  "team-review-requested",
  --- Dates
  "created",
  "updated",
  "closed",
  archived = { "true", "false" },
  linked = { "pr", "issue" },
  "org",
  --- Discussions
  ["answered-by"] = create_complete_user "answered-by",
  category = complete_category,
}

--- Complete function for search commands. This includes
--- Octo search and Octo pr/issue/discussion search
--- @param argLead string: The argument lead
--- @param cmdLine string: The command line
M.complete = function(argLead, cmdLine)
  if not string.match(argLead, ":") then
    local valid = {}
    for first, second in pairs(qualifiers) do
      local qualifier = type(first) == "number" and second or first
      if string.match(qualifier, argLead) then
        table.insert(valid, qualifier .. ":")
      end
    end
    return valid
  end

  local expected_qualifier = string.match(argLead, "([^:]+):")

  for first, second in pairs(qualifiers) do
    local qualifier, action
    if type(first) == "number" then
      qualifier = second
      action = function()
        return {}
      end
    else
      qualifier = first
      action = second
      if type(action) == "table" then
        action = function()
          return get_closest_valid(qualifier, second, argLead)
        end
      end
    end

    if qualifier == expected_qualifier then
      return action(argLead, cmdLine)
    end
  end

  return {}
end

return M
