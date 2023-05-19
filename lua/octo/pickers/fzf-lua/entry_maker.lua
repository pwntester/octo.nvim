local utils = require "octo.utils"

local M = {}

function M.gen_from_issue(issue_table)
  if not issue_table or vim.tbl_isempty(issue_table) then
    return nil
  end
  local kind = issue_table.__typename == "Issue" and "issue" or "pull_request"
  local filename
  if kind == "issue" then
    filename = utils.get_issue_uri(issue_table.repository.nameWithOwner, issue_table.number)
  else
    filename = utils.get_pull_request_uri(issue_table.repository.nameWithOwner, issue_table.number)
  end
  return {
    filename = filename,
    kind = kind,
    value = issue_table.number,
    ordinal = issue_table.number .. " " .. issue_table.title,
    obj = issue_table,
    repo = issue_table.repository.nameWithOwner,
  }
end

function M.gen_from_git_commits(entry)
  if not entry then
    return nil
  end

  return {
    value = entry.sha,
    parent = entry.parents[1].sha,
    ordinal = entry.sha .. " " .. entry.commit.message,
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

  TODO use these counts somehow :shrug:

  @param max_nameWithOwner Length of longest name + owner string.
  @param max_forkCount Length of longest fork count string.
  @param max_stargazerCount Length of longest stargazer count string.
  @param repo The raw repo table from GitHub.
]]
function M.gen_from_repo(max_nameWithOwner, max_forkCount, max_stargazerCount, repo)
  if not repo or vim.tbl_isempty(repo) then
    return nil
  end

  if repo.description == vim.NIL then
    repo.description = ""
  end

  return {
    filename = utils.get_repo_uri(_, repo),
    kind = "repo",
    value = repo.nameWithOwner,
    ordinal = repo.nameWithOwner .. " " .. repo.description,
    repo = repo,
  }
end

function M.gen_from_gist(gist)
  if not gist or vim.tbl_isempty(gist) then
    return
  end

  if gist.description == vim.NIL then
    gist.description = ""
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
    ordinal = template.name .. " " .. template.about,
    template = template,
  }
end

return M
