local entry_display = require "telescope.pickers.entry_display"
local bubbles = require "octo.ui.bubbles"
local utils = require "octo.utils"

local vim = vim

local M = {}

function M.gen_from_discussions(max_number)
  local make_display = function(entry)
    if not entry then
      return nil
    end

    local columns = {
      { entry.value, "TelescopeResultsNumber" },
      utils.get_icon(entry),
      { entry.obj.title },
    }
    local layout = {
      separator = " ",
      items = {
        { width = max_number },
        { width = 2 },
        { remaining = true },
      },
    }
    local displayer = entry_display.create(layout)

    return displayer(columns)
  end

  return function(obj)
    if not obj or vim.tbl_isempty(obj) then
      return nil
    end

    local kind = "discussion"
    local filename = utils.get_discussion_uri(obj.number, obj.repository.nameWithOwner)

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
        utils.get_icon(entry),
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

    local kind
    local typename = obj.__typename
    if typename == "Issue" then
      kind = "issue"
    elseif typename == "PullRequest" then
      kind = "pull_request"
    else
      kind = "discussion"
    end

    local filename
    if kind == "issue" then
      filename = utils.get_issue_uri(obj.number, obj.repository.nameWithOwner)
    elseif kind == "pull_request" then
      filename = utils.get_pull_request_uri(obj.number, obj.repository.nameWithOwner)
    else
      filename = utils.get_discussion_uri(obj.number, obj.respository.nameWithOwner)
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

function M.gen_from_milestone(title_width, show_description)
  title_width = title_width or 10

  local make_display = function(entry)
    if not entry then
      return nil
    end

    local columns, items
    if show_description then
      columns = {
        { entry.milestone.title, "OctoDetailsLabel" },
        { " " },
        { entry.milestone.description },
      }
      items = { { width = title_width }, { width = 1 }, { remaining = true } }
    else
      columns = {
        { entry.milestone.title, "OctoDetailsLabel" },
      }
      items = { { width = title_width } }
    end

    local displayer = entry_display.create {
      separator = "",
      items = items,
    }

    return displayer(columns)
  end

  return function(milestone)
    if not milestone or vim.tbl_isempty(milestone) then
      return nil
    end

    return {
      value = milestone.id,
      ordinal = milestone.title,
      display = make_display,
      milestone = milestone,
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

function M.gen_from_octo_actions(width)
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
        { width = width },
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

function M.gen_from_notification(opts)
  opts = opts or { show_repo_info = false }
  local make_display = function(entry)
    if not entry then
      return nil
    end

    local icons = utils.icons

    local columns = {
      entry.obj.unread == true and icons.notification[entry.kind].unread or icons.notification[entry.kind].read,
      { "#" .. (entry.obj.subject.url:match "/(%d+)$" or "NA") },
      { string.sub(entry.obj.repository.full_name, 1, 50), "TelescopeResultsNumber" },
      { string.sub(entry.obj.subject.title, 1, 100) },
    }
    local items = {
      { width = 2 },
      { width = 6 },
      { width = math.min(#entry.obj.repository.full_name, 50) },
      { width = math.min(#entry.obj.subject.title, 100) },
    }

    if not opts.show_repo_info then
      table.remove(columns, 3)
      table.remove(items, 3)
    end

    local displayer = entry_display.create {
      separator = " ",
      items = items,
    }

    return displayer(columns)
  end

  return function(notification)
    if not notification or vim.tbl_isempty(notification) then
      return nil
    end

    notification.kind = (function(type)
      if type == "Issue" then
        return "issue"
      elseif type == "PullRequest" then
        return "pull_request"
      end
      return "unknown"
    end)(notification.subject.type)

    if notification.kind == "unknown" then
      return nil
    end
    local ref = notification.subject.url:match "/(%d+)$"

    return {
      value = ref,
      ordinal = notification.subject.title .. " " .. notification.repository.full_name .. " " .. ref,
      display = make_display,
      obj = notification,
      repo = notification.repository.full_name,
      kind = notification.kind,
      thread_id = notification.id,
      url = notification.subject.url,
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
