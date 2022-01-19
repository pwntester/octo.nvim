local entry_display = require "telescope.pickers.entry_display"
local bubbles = require "octo.ui.bubbles"
local utils = require "octo.utils"

local M = {}

function M.gen_from_issue(max_number)
  local make_display = function(entry)
    if not entry then
      return nil
    end

    local columns = {
      { entry.issue.number, "TelescopeResultsNumber" },
      { entry.issue.title },
    }

    local displayer = entry_display.create {
      separator = " ",
      items = {
        { width = max_number },
        { remaining = true },
      },
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
      issue = issue,
    }
  end
end

function M.gen_from_pull_request(max_number)
  local make_display = function(entry)
    if not entry then
      return nil
    end

    local columns = {
      { entry.pull_request.number, "TelescopeResultsNumber" },
      { entry.pull_request.title },
    }

    local displayer = entry_display.create {
      separator = " ",
      items = {
        { width = max_number },
        { remaining = true },
      },
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
      pull_request = pull_request,
    }
  end
end

function M.gen_from_git_commits()
  local displayer = entry_display.create {
    separator = " ",
    items = {
      { width = 8 },
      { remaining = true },
    },
  }

  local make_display = function(entry)
    return displayer {
      { entry.value:sub(1, 7), "TelescopeResultsNumber" },
      vim.split(entry.msg, "\n")[1],
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
      author = string.format("%s <%s>", entry.commit.author.name, entry.commit.author.email),
      date = entry.commit.author.date,
    }
  end
end

function M.gen_from_git_changed_files()
  local displayer = entry_display.create {
    separator = " ",
    items = {
      { width = 8 },
      { width = string.len "modified" },
      { width = 5 },
      { width = 5 },
      { remaining = true },
    },
  }

  local make_display = function(entry)
    return displayer {
      { entry.value:sub(1, 7), "TelescopeResultsNumber" },
      { entry.change.status, "OctoDetailsLabel" },
      { string.format("+%d", entry.change.additions), "OctoPullAdditions" },
      { string.format("-%d", entry.change.deletions), "OctoPullDeletions" },
      vim.split(entry.msg, "\n")[1],
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
      change = entry,
    }
  end
end

function M.gen_from_review_thread(linenr_length)
  local make_display = function(entry)
    if not entry then
      return nil
    end

    local columns = {
      { entry.thread.path, "TelescopeResultsNumber" },
      { entry.thread.diffSide },
      { entry.thread.startLine },
      { entry.thread.line },
    }

    local displayer = entry_display.create {
      separator = " ",
      items = {
        { remaining = true },
        { width = 5 },
        { width = linenr_length },
        { width = linenr_length },
      },
    }
    return displayer(columns)
  end

  return function(thread)
    if not thread or vim.tbl_isempty(thread) then
      return nil
    end

    return {
      value = thread.path .. ":" .. thread.startLine .. ":" .. thread.line,
      ordinal = thread.path .. ":" .. thread.startLine .. ":" .. thread.line,
      display = make_display,
      thread = thread,
    }
  end
end

function M.gen_from_project()
  local make_display = function(entry)
    if not entry then
      return nil
    end

    local columns = {
      { entry.project.name },
    }

    local displayer = entry_display.create {
      separator = " ",
      items = {
        { remaining = true },
      },
    }

    return displayer(columns)
  end

  return function(project)
    if not project or vim.tbl_isempty(project) then
      return nil
    end

    return {
      value = project.id,
      ordinal = project.id .. " " .. project.name,
      display = make_display,
      project = project,
    }
  end
end

function M.gen_from_project_column()
  local make_display = function(entry)
    if not entry then
      return nil
    end

    local columns = {
      { entry.column.name },
    }

    local displayer = entry_display.create {
      separator = " ",
      items = {
        { remaining = true },
      },
    }

    return displayer(columns)
  end

  return function(column)
    if not column or vim.tbl_isempty(column) then
      return nil
    end
    return {
      value = column.id,
      ordinal = column.id .. " " .. column.name,
      display = make_display,
      column = column,
    }
  end
end

function M.gen_from_project_card()
  local make_display = function(entry)
    if not entry then
      return nil
    end

    local columns = {
      { entry.card.column.name },
      { string.format(" (%s)", entry.card.project.name), "OctoDetailsValue" },
    }

    local displayer = entry_display.create {
      separator = " ",
      items = {
        { width = 5 },
        { remaining = true },
      },
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
      card = card,
    }
  end
end

function M.gen_from_label()
  local make_display = function(entry)
    if not entry then
      return nil
    end

    local columns = bubbles.make_label_bubble(entry.label.name, entry.label.color)

    local displayer = entry_display.create {
      separator = "",
      items = {
        { width = 1 },
        { remaining = true },
        { width = 1 },
      },
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
      label = label,
    }
  end
end

function M.gen_from_team()
  local make_display = function(entry)
    if not entry then
      return nil
    end

    local columns = {
      { entry.team.name },
    }

    local displayer = entry_display.create {
      separator = "",
      items = {
        { remaining = true },
      },
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
      team = team,
    }
  end
end

function M.gen_from_user()
  local make_display = function(entry)
    if not entry then
      return nil
    end

    local columns = {
      { entry.user.login },
    }

    local displayer = entry_display.create {
      separator = "",
      items = {
        { remaining = true },
      },
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
      user = user,
    }
  end
end

function M.gen_from_repo(max_nameWithOwner, max_forkCount, max_stargazerCount)
  local make_display = function(entry)
    if not entry then
      return nil
    end

    local fork_str = ""
    if entry.repo.isFork then
      fork_str = "fork"
    end

    local access_str = "public"
    if entry.repo.isPrivate then
      access_str = "private"
    end

    local columns = {
      { string.sub(entry.repo.nameWithOwner, 1, 50), "TelescopeResultsNumber" },
      { "s:", "TelescopeResultsNumber" },
      { entry.repo.stargazerCount },
      { "f:", "TelescopeResultsNumber" },
      { entry.repo.forkCount },
      { access_str },
      { fork_str },
      { entry.repo.description },
    }

    local displayer = entry_display.create {
      separator = " ",
      items = {
        { width = math.min(max_nameWithOwner, 50) },
        { width = 2 },
        { width = max_stargazerCount },
        { width = 2 },
        { width = max_forkCount },
        { width = vim.fn.len "private" },
        { width = vim.fn.len "fork" },
        { remaining = true },
      },
    }

    return displayer(columns)
  end

  return function(repo)
    if not repo or vim.tbl_isempty(repo) then
      return nil
    end

    if repo.description == vim.NIL then
      repo.description = ""
    end

    return {
      value = repo.nameWithOwner,
      ordinal = repo.nameWithOwner .. " " .. repo.description,
      display = make_display,
      repo = repo,
    }
  end
end

function M.gen_from_gist()
  local make_display = function(entry)
    if not entry then
      return
    end

    local fork_str = ""
    if entry.gist.isFork then
      fork_str = "fork"
    end

    local access_str = "private"
    if entry.gist.isPublic then
      access_str = "public"
    end

    local description = entry.gist.description
    if (not description or utils.is_blank(description) or description == vim.NIL) and #entry.gist.files > 0 then
      description = entry.gist.files[1].name
    end

    local columns = {
      { access_str },
      { fork_str },
      { description, "TelescopeResultsNumber" },
    }

    local displayer = entry_display.create {
      separator = " ",
      items = {
        { width = vim.fn.len "private" },
        { width = vim.fn.len "fork" },
        { remaining = true },
      },
    }

    return displayer(columns)
  end

  return function(gist)
    if not gist or vim.tbl_isempty(gist) then
      return
    end

    if gist.description == vim.NIL then
      gist.description = ""
    end

    return {
      value = gist.name,
      ordinal = gist.name .. " " .. gist.description,
      display = make_display,
      gist = gist,
    }
  end
end

function M.gen_from_octo_commands(commands)
  local make_display = function(entry)
    if not entry then
      return nil
    end

    local columns = {
      {entry.value.object, "TelescopeResultsNumber"},
      {entry.value.name}
    }

    local displayer =
      entry_display.create {
      separator = "",
      items = {
        {width = 12},
        {remaining = true}
      }
    }

    return displayer(columns)
  end

  return function(command)
    if not command or vim.tbl_isempty(command) then
      return nil
    end

    return {
      value = command,
      ordinal = command.object .. " " .. command.name,
      display = make_display
    }
  end
end

return M
