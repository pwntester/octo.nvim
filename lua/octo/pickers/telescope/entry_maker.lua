local entry_display = require "telescope.pickers.entry_display"
local bubbles = require "octo.ui.bubbles"
local utils = require "octo.utils"

local M = {}

--- @class EntryObject
--- @field state string
--- @field isDraft boolean
--- @field stateReason string

--- @class Entry
--- @field kind string
--- @field obj EntryObject

--- @class Icon
--- @field [1] string The icon
--- @field [2] string|nil The highlight group for the icon
--- @see octo.ui.colors for the available highlight groups

-- Symbols found with "Telescope symbols"
local icons = {
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
  unknown = { " " },
}

--- Get the icon for the entry
---@param entry Entry: The entry to get the icon for
---@return Icon: The icon for the entry
local function get_icon(entry)
  local kind = entry.kind
  local state = entry.obj.state
  local isDraft = entry.obj.isDraft
  local stateReason = entry.obj.stateReason

  if kind == "issue" then
    if state == "OPEN" then
      return icons.issue.open
    elseif state == "CLOSED" and stateReason == "NOT_PLANNED" then
      return icons.issue.not_planned
    elseif state == "CLOSED" then
      return icons.issue.closed
    end
  elseif kind == "pull_request" then
    if state == "MERGED" then
      return icons.pull_request.merged
    elseif state == "CLOSED" then
      return icons.pull_request.closed
    elseif isDraft then
      return icons.pull_request.draft
    elseif state == "OPEN" then
      return icons.pull_request.open
    end
  end

  return icons.unknown
end

function M.gen_from_pull_request(max_number, username_col_len, branch_name_col_len, author_count)
  local make_display = function(entry)
    if not entry then
      return nil
    end

    local layout, columns
    columns = {
      { entry.value, "TelescopeResultsNumber" },
      { entry.obj.author.login },
      { entry.obj.headRefName },
      { entry.obj.title },
    }
    layout = {
      separator = " ",
      items = {
        { width = max_number },
        { width = username_col_len },
        { width = branch_name_col_len },
        { remaining = true },
      },
    }

    -- hide author column if there is just one author
    if author_count == 1 then
      table.remove(columns, 2)
      table.remove(layout.items, 2)
    end

    local displayer = entry_display.create(layout)

    return displayer(columns)
  end

  return function(obj)
    if not obj or vim.tbl_isempty(obj) then
      return nil
    end
    local filename = utils.get_pull_request_uri(obj.repository.nameWithOwner, obj.number)

    return {
      filename = filename,
      kind = "pull_request",
      value = obj.number,
      ordinal = obj.number .. " " .. obj.title .. " " .. obj.author.login .. " " .. obj.headRefName,
      display = make_display,
      obj = obj,
      repo = obj.repository.nameWithOwner,
    }
  end
end

function M.gen_from_issue(max_number, print_repo)
  local make_display = function(entry)
    if not entry then
      return nil
    end

    local layout, columns
    if print_repo then
      columns = {
        { entry.value, "TelescopeResultsNumber" },
        { entry.repo, "OctoDetailsLabel" },
        { entry.obj.title },
      }
      layout = {
        separator = " ",
        items = {
          { width = max_number },
          { width = 35 },
          { remaining = true },
        },
      }
    else
      columns = {
        { entry.value, "TelescopeResultsNumber" },
        get_icon(entry),
        { entry.obj.title },
      }
      layout = {
        separator = " ",
        items = {
          { width = max_number },
          { width = 2 },
          { remaining = true },
        },
      }
    end

    local displayer = entry_display.create(layout)

    return displayer(columns)
  end

  return function(obj)
    if not obj or vim.tbl_isempty(obj) then
      return nil
    end
    local kind = obj.__typename == "Issue" and "issue" or "pull_request"
    local filename
    if kind == "issue" then
      filename = utils.get_issue_uri(obj.repository.nameWithOwner, obj.number)
    else
      filename = utils.get_pull_request_uri(obj.repository.nameWithOwner, obj.number)
    end
    return {
      filename = filename,
      kind = kind,
      value = obj.number,
      ordinal = obj.number .. " " .. obj.title,
      display = make_display,
      obj = obj,
      repo = obj.repository.nameWithOwner,
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
      parent = entry.parents[1].sha,
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
  local function create_name(user, parens)
    if not user.name or user.name == vim.NIL then
      return user.login
    end

    if parens then
      return user.login .. " (" .. user.name .. ")"
    end

    return user.login .. user.name
  end

  local make_display = function(entry)
    if not entry then
      return nil
    end

    local columns = {
      { create_name(entry.user, true) },
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
      ordinal = create_name(user, false),
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
      filename = utils.get_repo_uri(_, repo),
      kind = "repo",
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

function M.gen_from_octo_actions()
  local make_display = function(entry)
    if not entry then
      return nil
    end

    local columns = {
      { entry.action.object, "TelescopeResultsNumber" },
      { entry.action.name },
    }

    local displayer = entry_display.create {
      separator = "",
      items = {
        { width = 12 },
        { remaining = true },
      },
    }

    return displayer(columns)
  end

  return function(action)
    if not action or vim.tbl_isempty(action) then
      return nil
    end

    return {
      value = action.name,
      ordinal = action.object .. " " .. action.name,
      display = make_display,
      action = action,
    }
  end
end

function M.gen_from_issue_templates()
  local make_display = function(entry)
    if not entry then
      return nil
    end

    local columns = {
      { entry.template.name, "TelescopeResultsNumber" },
      { entry.template.about },
    }

    local displayer = entry_display.create {
      separator = "",
      items = {
        { width = 25 },
        { remaining = true },
      },
    }

    return displayer(columns)
  end

  return function(template)
    if not template or vim.tbl_isempty(template) then
      return nil
    end

    return {
      value = template.name,
      ordinal = template.name .. " " .. template.about,
      display = make_display,
      template = template,
    }
  end
end

return M
