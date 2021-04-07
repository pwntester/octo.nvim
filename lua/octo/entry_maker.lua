local entry_display = require "telescope.pickers.entry_display"
local util = require "octo.util"
local bubbles = require "octo.ui.bubbles"
local format = string.format

local M = {}

function M.gen_from_issue(max_number)
  local make_display = function(entry)
    if not entry then
      return nil
    end

    local columns = {
      {entry.issue.number, "TelescopeResultsNumber"},
      {entry.issue.title}
    }

    local displayer =
      entry_display.create {
      separator = " ",
      items = {
        {width = max_number},
        {remaining = true}
      }
    }

    return displayer(columns)
  end

  return function(issue)
    if not issue or vim.tbl_isempty(issue) then
      return nil
    end

    return {
      value = issue.number,
      ordinal = issue.number .. " " .. issue.title,
      display = make_display,
      issue = issue
    }
  end
end

function M.gen_from_pull_request(max_number)
  local make_display = function(entry)
    if not entry then
      return nil
    end

    local columns = {
      {entry.pull_request.number, "TelescopeResultsNumber"},
      {entry.pull_request.title}
    }

    local displayer =
      entry_display.create {
      separator = " ",
      items = {
        {width = max_number},
        {remaining = true}
      }
    }

    return displayer(columns)
  end

  return function(pull_request)
    if not pull_request or vim.tbl_isempty(pull_request) then
      return nil
    end

    return {
      value = pull_request.number,
      ordinal = pull_request.number .. " " .. pull_request.title,
      display = make_display,
      pull_request = pull_request
    }
  end
end

function M.gen_from_git_commits()
  local displayer =
    entry_display.create {
    separator = " ",
    items = {
      {width = 8},
      {remaining = true}
    }
  }

  local make_display = function(entry)
    return displayer {
      {entry.value:sub(1, 7), "TelescopeResultsNumber"},
      vim.split(entry.msg, "\n")[1]
    }
  end

  return function(entry)
    if not entry then
      return nil
    end

    return {
      value = entry.sha,
      ordinal = entry.sha .. " " .. entry.commit.message,
      msg = entry.commit.message,
      display = make_display,
      author = format("%s <%s>", entry.commit.author.name, entry.commit.author.email),
      date = entry.commit.author.date
    }
  end
end

function M.gen_from_git_changed_files()
  local displayer =
    entry_display.create {
    separator = " ",
    items = {
      {width = 8},
      {width = string.len("modified")},
      {width = 5},
      {width = 5},
      {remaining = true}
    }
  }

  local make_display = function(entry)
    return displayer {
      {entry.value:sub(1, 7), "TelescopeResultsNumber"},
      {entry.change.status, "OctoNvimDetailsLabel"},
      {format("+%d", entry.change.additions), "OctoNvimPullAdditions"},
      {format("-%d", entry.change.deletions), "OctoNvimPullDeletions"},
      vim.split(entry.msg, "\n")[1]
    }
  end

  return function(entry)
    if not entry then
      return nil
    end

    return {
      value = entry.sha,
      ordinal = entry.sha .. " " .. entry.filename,
      msg = entry.filename,
      display = make_display,
      change = entry
    }
  end
end

function M.gen_from_review_thread(linenr_length)
  local make_display = function(entry)
    if not entry then return nil end

    local columns = {
      {entry.thread.path, "TelescopeResultsNumber"},
      {entry.thread.diffSide},
      {entry.thread.startLine},
      {entry.thread.line}
    }

    local displayer =
      entry_display.create {
      separator = " ",
      items = {
        {remaining = true},
        {width = 5},
        {width = linenr_length},
        {width = linenr_length}
      }
    }
    return displayer(columns)
  end

  return function(thread)
    if not thread or vim.tbl_isempty(thread) then
      return nil
    end

    return {
      value = thread.path..":"..thread.startLine..":"..thread.line,
      ordinal = thread.path..":"..thread.startLine..":"..thread.line,
      display = make_display,
      thread = thread
    }
  end
end

function M.gen_from_project()
  local make_display = function(entry)
    if not entry then
      return nil
    end

    local columns = {
      {entry.project.name}
    }

    local displayer =
      entry_display.create {
      separator = " ",
      items = {
        {remaining = true}
      }
    }

    return displayer(columns)
  end

  return function(project)
    if not project or vim.tbl_isempty(project) then
      return nil
    end

    return {
      value = project.id,
      ordinal = project.id.. " " .. project.name,
      display = make_display,
      project = project
    }
  end
end

function M.gen_from_project_column()
  local make_display = function(entry)
    if not entry then
      return nil
    end

    local columns = {
      {entry.column.name}
    }

    local displayer =
      entry_display.create {
      separator = " ",
      items = {
        {remaining = true}
      }
    }

    return displayer(columns)
  end

  return function(column)
    if not column or vim.tbl_isempty(column) then
      return nil
    end

    return {
      value = column.id,
      ordinal = column.id.. " " .. column.name,
      display = make_display,
      column = column
    }
  end
end

function M.gen_from_project_card()
  local make_display = function(entry)
    if not entry then
      return nil
    end

    local columns = {
      {entry.card.column.name},
      {format(" (%s)", entry.card.project.name), "OctoNvimDetailsValue"},
    }

    local displayer =
      entry_display.create {
      separator = " ",
      items = {
        {width = 5},
        {remaining = true}
      }
    }

    return displayer(columns)
  end

  return function(card)
    if not card or vim.tbl_isempty(card) then
      return nil
    end

    return {
      value = card.id,
      ordinal = card.project.name .. " " .. card.column.name,
      display = make_display,
      card = card
    }
  end
end

function M.gen_from_label()
  local make_display = function(entry)
    if not entry then
      return nil
    end

    local columns = bubbles.make_label_bubble(
      entry.label.name,
      entry.label.color
    )

    local displayer =
      entry_display.create {
      separator = "",
      items = {
        {width = 1},
        {remaining = true},
        {width = 1}
      }
    }

    return displayer(columns)
  end

  return function(label)
    if not label or vim.tbl_isempty(label) then
      return nil
    end

    return {
      value = label.id,
      ordinal = label.name,
      display = make_display,
      label = label
    }
  end
end

function M.gen_from_team()
  local make_display = function(entry)
    if not entry then
      return nil
    end

    local columns = {
      {entry.team.name},
    }

    local displayer =
      entry_display.create {
      separator = "",
      items = {
        {remaining = true},
      }
    }

    return displayer(columns)
  end

  return function(team)
    if not team or vim.tbl_isempty(team) then
      return nil
    end

    return {
      value = team.id,
      ordinal = team.name,
      display = make_display,
      team = team
    }
  end
end

function M.gen_from_user()
  local make_display = function(entry)
    if not entry then
      return nil
    end

    local columns = {
      {entry.user.login}
    }

    local displayer =
      entry_display.create {
      separator = "",
      items = {
        {remaining = true},
      }
    }

    return displayer(columns)
  end

  return function(user)
    if not user or vim.tbl_isempty(user) then
      return nil
    end

    return {
      value = user.id,
      ordinal = user.login,
      display = make_display,
      user = user
    }
  end
end

return M
