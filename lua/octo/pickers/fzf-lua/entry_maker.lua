---@diagnostic disable
local utils = require "octo.utils"
local fzf = require "fzf-lua"

local M = {}

---@param issue_table table
---@return table|nil
function M.gen_from_issue(issue_table)
  if not issue_table or vim.tbl_isempty(issue_table) then
    return nil
  end

  local kind, filename, repo, ordinal

  if issue_table.__typename == "Issue" then
    kind = "issue"
    filename = utils.get_issue_uri(issue_table.number, issue_table.repository.nameWithOwner)
    repo = issue_table.repository.nameWithOwner
    ordinal = issue_table.number .. " " .. issue_table.title
  elseif issue_table.__typename == "PullRequest" then
    kind = "pull_request"
    filename = utils.get_pull_request_uri(issue_table.number, issue_table.repository.nameWithOwner)
    repo = issue_table.repository.nameWithOwner
    ordinal = issue_table.number .. " " .. issue_table.title
  elseif issue_table.__typename == "Discussion" then
    kind = "discussion"
    filename = utils.get_discussion_uri(issue_table.number, issue_table.repository.nameWithOwner)
    repo = issue_table.repository.nameWithOwner
    ordinal = issue_table.number .. " " .. issue_table.title
  elseif issue_table.__typename == "Repository" then
    kind = "repo"
    filename = utils.get_repo_uri(nil, issue_table.nameWithOwner)
    repo = issue_table.nameWithOwner
    ordinal = issue_table.number
  end

  return {
    filename = filename,
    kind = kind,
    value = issue_table.number,
    ordinal = ordinal,
    obj = issue_table,
    repo = repo,
  }
end

---@class octo.NotificationFromREST
---@field subject { type: "Issue" | "PullRequest" | "Discussion" | "Release", url: string, title: string, latest_comment_url?: string }
---@field repository { full_name: string }
---@field id string
---@field unread boolean

---@class octo.NotificationEntry
---@field value string
---@field ordinal string
---@field obj octo.NotificationFromREST
---@field repo string
---@field kind "issue" | "pull_request" | "discussion" | "release"
---@field thread_id string
---@field url string
---@field tag_name? string

---@param notification octo.NotificationFromREST
---@return octo.NotificationEntry?
function M.gen_from_notification(notification)
  if not notification or vim.tbl_isempty(notification) then
    return nil
  end

  local notification_kind = (function(type)
    if type == "Issue" then
      return "issue"
    elseif type == "PullRequest" then
      return "pull_request"
    elseif type == "Discussion" then
      return "discussion"
    elseif type == "Release" then
      return "release"
    end
    return "unknown"
  end)(notification.subject.type)

  if notification_kind == "unknown" then
    return nil
  end
  ---@type string
  local ref = notification.subject.url:match "/(%d+)$"

  return {
    value = ref,
    ordinal = notification.subject.title .. " " .. notification.repository.full_name .. " " .. ref,
    obj = notification,
    repo = notification.repository.full_name,
    kind = notification_kind,
    thread_id = notification.id,
    url = notification.subject.url,
  }
end

function M.gen_from_git_commits(entry)
  if not entry then
    return nil
  end

  local trimmed_message = string.gsub(entry.commit.message, "\n.*", "")

  return {
    value = entry.sha,
    parent = entry.parents[1].sha,
    ordinal = entry.sha .. " " .. trimmed_message,
    msg = entry.commit.message,
    author = string.format("%s <%s>", entry.commit.author.name, entry.commit.author.email),
    date = entry.commit.author.date,
  }
end

function M.gen_from_git_changed_files(entry)
  if not entry then
    return nil
  end

  return {
    value = entry.sha,
    ordinal = entry.sha .. " " .. entry.filename,
    msg = entry.filename,
    change = entry,
  }
end

function M.gen_from_review_thread(linenr_length, thread)
  if not thread or vim.tbl_isempty(thread) then
    return nil
  end

  return {
    value = thread.path .. ":" .. thread.startLine .. ":" .. thread.line,
    ordinal = thread.path .. ":" .. thread.startLine .. ":" .. thread.line,
    thread = thread,
  }
end

function M.gen_from_project(project)
  if not project or vim.tbl_isempty(project) then
    return nil
  end

  return {
    value = project.id,
    ordinal = project.id .. " " .. project.name,
    project = project,
  }
end

function M.gen_from_project_column(column)
  if not column or vim.tbl_isempty(column) then
    return nil
  end
  return {
    value = column.id,
    ordinal = column.id .. " " .. column.name,
    column = column,
  }
end

function M.gen_from_project_card(card)
  if not card or vim.tbl_isempty(card) then
    return nil
  end

  return {
    value = card.id,
    ordinal = card.project.name .. " " .. card.column.name,
    card = card,
  }
end

function M.gen_from_project_v2(project)
  if not project or vim.tbl_isempty(project) then
    return nil
  end

  local title = project.title

  if project.closed then
    title = fzf.utils.ansi_from_hl("Comment", project.title) .. " " .. fzf.utils.ansi_from_hl("OctoPurple", "(closed)")
  end

  return {
    id = project.id,
    repo = project.owner.login,
    value = project.number,
    ordinal = project.id .. " " .. title,
    kind = "project",
    obj = project,
  }
end

function M.gen_from_project_v2_column(column)
  if not column or vim.tbl_isempty(column) then
    return nil
  end
  return {
    value = column.id,
    ordinal = column.id .. " " .. column.name,
    column = column,
  }
end

function M.gen_from_label(label)
  if not label or vim.tbl_isempty(label) then
    return nil
  end

  return {
    value = label.id,
    ordinal = label.name,
    label = label,
  }
end

function M.gen_from_team(team)
  if not team or vim.tbl_isempty(team) then
    return nil
  end

  return {
    value = team.id,
    ordinal = team.name,
    team = team,
  }
end

function M.gen_from_user(user)
  if not user or vim.tbl_isempty(user) then
    return nil
  end

  return {
    value = user.id,
    ordinal = user.login,
    user = user,
  }
end

--[[
  Generates an entry from a raw repo table.

  TODO use these in Phase 2. Repo is not a part of the first change.

  @param max_nameWithOwner Length of longest name + owner string.
  @param max_forkCount Length of longest fork count string.
  @param max_stargazerCount Length of longest stargazer count string.
  @param repo The raw repo table from GitHub.
]]
function M.gen_from_repo(repo)
  if not repo or vim.tbl_isempty(repo) then
    return nil, nil
  end

  if repo.description == vim.NIL then
    repo.description = ""
  end

  local entry = {
    filename = utils.get_repo_uri(_, repo),
    kind = "repo",
    value = repo.nameWithOwner,
    ordinal = repo.nameWithOwner .. " " .. repo.description,
    repo = repo,
  }

  local name = fzf.utils.ansi_from_hl("Directory", entry.repo.nameWithOwner)
  local fork_str = ""
  if entry.repo.isFork then
    fork_str = fzf.utils.ansi_from_hl("Comment", "fork")
  end

  local access_str = fzf.utils.ansi_from_hl("Directory", "public")
  if entry.repo.isPrivate then
    access_str = fzf.utils.ansi_from_hl("WarningMsg", "private")
  end

  local metadata = string.format("(%s)", table.concat({ fork_str, access_str }, ", "))
  local description = fzf.utils.ansi_from_hl("Comment", entry.repo.description)
  local entry_str = table.concat({
    name,
    metadata,
    description,
  }, " ")

  return entry, entry_str
end

function M.gen_from_gist(gist)
  if not gist or vim.tbl_isempty(gist) then
    return
  end

  if gist.description == vim.NIL or gist.description == "" then
    gist.description = gist.name .. " (no description provided)"
  end

  return {
    value = gist.name,
    ordinal = gist.name .. " " .. gist.description,
    gist = gist,
  }
end

function M.gen_from_octo_actions(action)
  if not action or vim.tbl_isempty(action) then
    return nil
  end

  return {
    value = action.name,
    ordinal = action.object .. " " .. action.name,
    action = action,
  }
end

function M.gen_from_issue_templates(template)
  if not template or vim.tbl_isempty(template) then
    return nil
  end

  return {
    value = template.name,
    friendly_title = template.name .. " " .. fzf.utils.ansi_from_hl("Comment", template.about),
    ordinal = template.name .. " " .. template.about,
    template = template,
  }
end

return M
