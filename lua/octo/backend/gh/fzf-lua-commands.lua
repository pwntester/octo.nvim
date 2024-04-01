local utils = require "octo.utils"
local cli = require "octo.backend.gh.cli"
local graphql = require "octo.backend.gh.graphql"
local writers = require "octo.ui.writers"

local picker_utils = require "octo.pickers.fzf-lua.pickers.utils"
local entry_maker = require "octo.pickers.fzf-lua.entry_maker"
local fzf = require "fzf-lua"

local M = {}

---@param entry table
---@param tmpbuf integer bufnr
function M.fzf_lua_default_issue(entry, tmpbuf)
  local repo = entry.repo
  local kind = entry.kind
  local number = entry.value
  local owner, name = utils.split_repo(repo)
  local query
  if kind == "issue" then
    query = graphql("issue_query", owner, name, number, _G.octo_pv2_fragment)
  elseif kind == "pull_request" then
    query = graphql("pull_request_query", owner, name, number, _G.octo_pv2_fragment)
  end
  cli.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        vim.api.nvim_err_writeln(stderr)
      elseif output and vim.api.nvim_buf_is_valid(tmpbuf) then
        local result = vim.fn.json_decode(output)
        local obj
        if kind == "issue" then
          obj = result.data.repository.issue
        elseif kind == "pull_request" then
          obj = result.data.repository.pullRequest
        end
        writers.write_title(tmpbuf, obj.title, 1)
        writers.write_details(tmpbuf, obj)
        writers.write_body(tmpbuf, obj)
        writers.write_state(tmpbuf, obj.state:upper(), number)
        local reactions_line = vim.api.nvim_buf_line_count(tmpbuf) - 1
        writers.write_block(tmpbuf, { "", "" }, reactions_line)
        writers.write_reactions(tmpbuf, obj.reactionGroups, reactions_line)
        vim.api.nvim_buf_set_option(tmpbuf, "filetype", "octo")
      end
    end,
  }
end

---@param kind string
---@param number number
---@param owner string
---@param name string
---@param tmpbuf integer bufnr
function M.fzf_lua_previewer_search(kind, number, owner, name, tmpbuf)
  local query
  if kind == "issue" then
    query = graphql("issue_query", owner, name, number, _G.octo_pv2_fragment)
  elseif kind == "pull_request" then
    query = graphql("pull_request_query", owner, name, number)
    query = graphql("pull_request_query", owner, name, number, _G.octo_pv2_fragment)
  end
  cli.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        vim.api.nvim_err_writeln(stderr)
      elseif output and vim.api.nvim_buf_is_valid(tmpbuf) then
        local result = vim.fn.json_decode(output)
        local obj
        if kind == "issue" then
          obj = result.data.repository.issue
        elseif kind == "pull_request" then
          obj = result.data.repository.pullRequest
        end
        writers.write_title(tmpbuf, obj.title, 1)
        writers.write_details(tmpbuf, obj)
        writers.write_body(tmpbuf, obj)
        writers.write_state(tmpbuf, obj.state:upper(), number)
        local reactions_line = vim.api.nvim_buf_line_count(tmpbuf) - 1
        writers.write_block(tmpbuf, { "", "" }, reactions_line)
        writers.write_reactions(tmpbuf, obj.reactionGroups, reactions_line)
        vim.api.nvim_buf_set_option(tmpbuf, "filetype", "octo")
      end
    end,
  }
end

---@param repo string
---@param number integer
function M.fzf_lua_default_commit(repo, number)
  local url = string.format("/repos/%s/commits/%s", repo, number)
  local cmd = table.concat({ "gh", "api", "--paginate", url, "-H", "'Accept: application/vnd.github.v3.diff'" }, " ")
  local proc = io.popen(cmd, "r")
  local output
  if proc ~= nil then
    output = proc:read "*a"
    proc:close()
  else
    output = "Failed to read from " .. url
  end

  return output
end

---@param buffer OctoBuffer
---@param repo string
---@param tmpbuf integer bufnr
function M.fzf_lua_previewer_repos(buffer, repo, tmpbuf)
  local owner, name = utils.split_repo(repo)
  local query = graphql("repository_query", owner, name)
  cli.run {
    args = { "api", "graphql", "--paginate", "--jq", ".", "-f", string.format("query=%s", query) },
    cb = function(output, _)
      if vim.api.nvim_buf_is_valid(tmpbuf) then
        local resp = vim.fn.json_decode(output)
        buffer.node = resp.data.repository
        buffer:render_repo()
      end
    end,
  }
end

---@param formatted_issues table
---@param repo string
---@param order_by OctoConfigOrderBy
---@param filter string
function M.fzf_lua_issues(formatted_issues, repo, order_by, filter, fzf_cb)
  local owner, name = utils.split_repo(repo)
  local query = graphql("issues_query", owner, name, filter, order_by.field, order_by.direction, { escape = false })

  cli.run {
    args = {
      "api",
      "graphql",
      "--paginate",
      "--jq",
      ".",
      "-f",
      string.format("query=%s", query),
    },
    stream_cb = function(data, err)
      if err and not utils.is_blank(err) then
        utils.error(err)
        fzf_cb()
      elseif data then
        local resp = utils.aggregate_pages(data, "data.repository.issues.nodes")
        local issues = resp.data.repository.issues.nodes

        for _, issue in ipairs(issues) do
          local entry = entry_maker.gen_from_issue(issue)

          if entry ~= nil then
            formatted_issues[entry.ordinal] = entry
            local prefix = fzf.utils.ansi_from_hl("Comment", entry.value)
            fzf_cb(prefix .. " " .. entry.obj.title)
          end
        end
      end
    end,
    cb = function()
      fzf_cb()
    end,
  }
end

---@param formatted_gists table
---@param privacy string
function M.fzf_lua_gists(formatted_gists, privacy, fzf_cb)
  local query = graphql("gists_query", privacy)

  cli.run {
    args = { "api", "graphql", "--paginate", "--jq", ".", "-f", string.format("query=%s", query) },
    stream_cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
      elseif output then
        local resp = utils.aggregate_pages(output, "data.viewer.gists.nodes")
        local gists = resp.data.viewer.gists.nodes

        for _, gist in ipairs(gists) do
          local entry = entry_maker.gen_from_gist(gist)

          if entry ~= nil then
            formatted_gists[entry.ordinal] = entry
            fzf_cb(entry.ordinal)
          end
        end
      end

      fzf_cb()
    end,
    cb = function()
      fzf_cb()
    end,
  }
end

---@param formatted_pulls table
---@param repo string
---@param order_by OctoConfigOrderBy
---@param filter string
function M.fzf_lua_pull_requests(formatted_pulls, repo, order_by, filter, fzf_cb)
  local owner, name = utils.split_repo(repo)
  local query =
    graphql("pull_requests_query", owner, name, filter, order_by.field, order_by.direction, { escape = false })
  cli.run {
    args = {
      "api",
      "graphql",
      "--paginate",
      "--jq",
      ".",
      "-f",
      string.format("query=%s", query),
    },
    stream_cb = function(data, err)
      if err and not utils.is_blank(err) then
        utils.error(err)
        fzf_cb()
      elseif data then
        local resp = utils.aggregate_pages(data, "data.repository.pullRequests.nodes")
        local pull_requests = resp.data.repository.pullRequests.nodes

        for _, pull in ipairs(pull_requests) do
          local entry = entry_maker.gen_from_issue(pull)

          if entry ~= nil then
            formatted_pulls[entry.ordinal] = entry
            local highlight
            if entry.obj.isDraft then
              highlight = "OctoSymbol"
            else
              highlight = "OctoStateOpen"
            end
            local prefix = fzf.utils.ansi_from_hl(highlight, entry.value)
            fzf_cb(prefix .. " " .. entry.obj.title)
          end
        end
      end
    end,
    cb = function()
      fzf_cb()
    end,
  }
end

---@param formatted_commits table
---@param buffer OctoBuffer
function M.fzf_lua_commits(formatted_commits, buffer, fzf_cb)
  local url = string.format("repos/%s/pulls/%d/commits", buffer.repo, buffer.number)
  cli.run {
    args = { "api", "--paginate", url },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
      elseif output then
        local results = vim.fn.json_decode(output)

        for _, result in ipairs(results) do
          local entry = entry_maker.gen_from_git_commits(result)

          if entry ~= nil then
            formatted_commits[entry.ordinal] = entry
            fzf_cb(entry.ordinal)
          end
        end
      end
      fzf_cb()
    end,
  }
end

---@param formatted_commits table
---@param current_review Review
---@param make_full_pr function
function M.fzf_lua_review_commits(formatted_commits, current_review, make_full_pr, fzf_cb)
  local url =
    string.format("repos/%s/pulls/%d/commits", current_review.pull_request.repo, current_review.pull_request.number)
  cli.run {
    args = { "api", "--paginate", url },
    cb = function(output, err)
      if err and not utils.is_blank(err) then
        utils.error(err)
        fzf_cb()
      elseif output then
        local results = vim.fn.json_decode(output)

        if #formatted_commits == 0 then
          local full_pr = entry_maker.gen_from_git_commits(make_full_pr(current_review))
          formatted_commits["000 [[ENTIRE PULL REQUEST]]"] = full_pr
          fzf_cb "000 [[ENTIRE PULL REQUEST]]"
        end

        for _, commit in ipairs(results) do
          local entry = entry_maker.gen_from_git_commits(commit)

          if entry ~= nil then
            formatted_commits[entry.ordinal] = entry
            fzf_cb(entry.ordinal)
          end
        end
      end

      fzf_cb()
    end,
  }
end

---@param formatted_files table
---@param buffer OctoBuffer
function M.fzf_lua_changed_files(formatted_files, buffer, fzf_cb)
  local url = string.format("repos/%s/pulls/%d/files", buffer.repo, buffer.number)
  cli.run {
    args = { "api", "--paginate", url },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
      elseif output then
        local results = vim.fn.json_decode(output)

        for _, result in ipairs(results) do
          local entry = entry_maker.gen_from_git_changed_files(result)

          if entry ~= nil then
            formatted_files[entry.ordinal] = entry
            fzf_cb(entry.ordinal)
          end
        end
      end

      fzf_cb()
    end,
  }
end

---@param co thread
---@param prompt string
function M.fzf_lua_search(co, prompt, fzf_cb)
  local output = cli.run {
    args = { "api", "graphql", "-f", string.format("query=%s", graphql("search_query", prompt)) },
    mode = "sync",
  }

  if not output then
    return {}
  end

  local resp = vim.fn.json_decode(output)
  local max_id_length = 1
  for _, issue in ipairs(resp.data.search.nodes) do
    local s = tostring(issue.number)
    if #s > max_id_length then
      max_id_length = #s
    end
  end

  for _, issue in ipairs(resp.data.search.nodes) do
    vim.schedule(function()
      handle_entry(fzf_cb, issue, max_id_length, formatted_items, co)
    end)
    coroutine.yield()
  end
end

---@param formatted_projects table
---@param buffer OctoBuffer
function M.fzf_lua_select_target_project_column(formatted_projects, buffer, fzf_cb)
  local owner, name = utils.split_repo(buffer.repo)
  local query = graphql("projects_query", owner, name, vim.g.octo_viewer, owner)
  cli.run {
    args = { "api", "graphql", "--paginate", "-f", string.format("query=%s", query) },
    cb = function(output)
      if output then
        local resp = vim.fn.json_decode(output)

        local projects = {}
        local user_projects = resp.data.user and resp.data.user.projects.nodes or {}
        local repo_projects = resp.data.repository and resp.data.repository.projects.nodes or {}
        local org_projects = not resp.errors and resp.data.organization.projects.nodes or {}
        vim.list_extend(projects, repo_projects)
        vim.list_extend(projects, user_projects)
        vim.list_extend(projects, org_projects)

        if #projects == 0 then
          utils.error(string.format("There are no matching projects for %s.", buffer.repo))
          fzf_cb()
        end

        for _, project in ipairs(projects) do
          local entry = entry_maker.gen_from_project(project)

          if entry ~= nil then
            formatted_projects[entry.ordinal] = entry
            fzf_cb(entry.ordinal)
          end
        end
      end

      fzf_cb()
    end,
  }
end

---@param formatted_projects table
---@param buffer OctoBuffer
function M.fzf_lua_select_target_project_column_v2(formatted_projects, buffer, fzf_cb)
  local owner, name = utils.split_repo(buffer.repo)
  local query = graphql("projects_query_v2", owner, name, vim.g.octo_viewer, owner)
  cli.run {
    args = { "api", "graphql", "--paginate", "-f", string.format("query=%s", query) },
    cb = function(output)
      if output then
        local resp = vim.fn.json_decode(output)

        local unsorted_projects = {}
        local user_projects = resp.data.user and resp.data.user.projects.nodes or {}
        local repo_projects = resp.data.repository and resp.data.repository.projects.nodes or {}
        local org_projects = not resp.errors and resp.data.organization.projects.nodes or {}
        vim.list_extend(unsorted_projects, repo_projects)
        vim.list_extend(unsorted_projects, user_projects)
        vim.list_extend(unsorted_projects, org_projects)

        local projects = {}
        for _, project in ipairs(unsorted_projects) do
          if project.closed then
            table.insert(projects, #projects + 1, project)
          else
            table.insert(projects, 0, project)
          end
        end

        if #projects == 0 then
          utils.error(string.format("There are no matching projects for %s.", buffer.repo))
          fzf_cb()
        end

        for _, project in ipairs(projects) do
          local entry = entry_maker.gen_from_project_v2(project)

          if entry ~= nil then
            formatted_projects[entry.ordinal] = entry
            fzf_cb(entry.ordinal)
          end
        end
      end

      fzf_cb()
    end,
  }
end

---@param buffer OctoBuffer
function M.fzf_lua_select_label(buffer, fzf_cb)
  local owner, name = utils.split_repo(buffer.repo)
  local query = graphql("labels_query", owner, name)
  cli.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
      elseif output then
        local resp = vim.fn.json_decode(output)
        local labels = resp.data.repository.labels.nodes

        for _, label in ipairs(labels) do
          local colored_name = picker_utils.color_string_with_hex(label.name, "#" .. label.color)
          fzf_cb(string.format("%s %s", label.id, colored_name))
        end
      end

      fzf_cb()
    end,
  }
end

---@param buffer OctoBuffer
function M.fzf_lua_select_assigned_label(buffer, fzf_cb)
  local owner, name = utils.split_repo(buffer.repo)
  local query, key
  if buffer:isIssue() then
    query = graphql("issue_labels_query", owner, name, buffer.number)
    key = "issue"
  elseif buffer:isPullRequest() then
    query = graphql("pull_request_labels_query", owner, name, buffer.number)
    key = "pullRequest"
  end
  cli.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
      elseif output then
        local resp = vim.fn.json_decode(output)
        local labels = resp.data.repository[key].labels.nodes

        for _, label in ipairs(labels) do
          local colored_name = picker_utils.color_string_with_hex(label.name, "#" .. label.color)
          fzf_cb(string.format("%s %s", label.id, colored_name))
        end
      end

      fzf_cb()
    end,
  }
end

---@param formatted_users table
---@param prompt string
function M.fzf_lua_get_users(formatted_users, prompt)
  local query = graphql("users_query", prompt)
  local output = cli.run {
    args = { "api", "graphql", "--paginate", "-f", string.format("query=%s", query) },
    mode = "sync",
  }
  if output then
    local users = {}
    local orgs = {}
    local responses = utils.get_pages(output)
    for _, resp in ipairs(responses) do
      for _, user in ipairs(resp.data.search.nodes) do
        if not user.teams then
          -- regular user
          if not vim.tbl_contains(vim.tbl_keys(users), user.login) then
            users[user.login] = {
              id = user.id,
              login = user.login,
            }
          end
        elseif user.teams and user.teams.totalCount > 0 then
          -- organization, collect all teams
          if not vim.tbl_contains(vim.tbl_keys(orgs), user.login) then
            orgs[user.login] = {
              id = user.id,
              login = user.login,
              teams = user.teams.nodes,
            }
          else
            vim.list_extend(orgs[user.login].teams, user.teams.nodes)
          end
        end
      end
    end

    -- TODO highlight orgs?
    local format_display = function(thing)
      return thing.id .. " " .. thing.login
    end

    local results = {}
    -- process orgs with teams
    for _, user in pairs(users) do
      user.ordinal = format_display(user)
      formatted_users[user.ordinal] = user
      table.insert(results, user.ordinal)
    end
    for _, org in pairs(orgs) do
      org.login = string.format("%s (%d)", org.login, #org.teams)
      org.ordinal = format_display(org)
      formatted_users[org.ordinal] = org
      table.insert(results, org.ordinal)
    end
    return results
  else
    return {}
  end
end

---@param buffer OctoBuffer
function M.fzf_lua_select_assignee(buffer, fzf_cb)
  local owner, name = utils.split_repo(buffer.repo)
  local query, key
  if buffer:isIssue() then
    query = graphql("issue_assignees_query", owner, name, buffer.number)
    key = "issue"
  elseif buffer:isPullRequest() then
    query = graphql("pull_request_assignees_query", owner, name, buffer.number)
    key = "pullRequest"
  end

  cli.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
      elseif output then
        local resp = vim.fn.json_decode(output)
        local assignees = resp.data.repository[key].assignees.nodes

        for _, user in ipairs(assignees) do
          fzf_cb(string.format("%s %s", user.id, user.login))
        end
      end

      fzf_cb()
    end,
  }
end

---@param formatted_repos table
---@param login string
function M.fzf_lua_repos(formatted_repos, login, fzf_cb)
  local query = graphql("repos_query", login)
  cli.run {
    args = { "api", "graphql", "--paginate", "--jq", ".", "-f", string.format("query=%s", query) },
    stream_cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
        fzf_cb()
      elseif output then
        local resp = utils.aggregate_pages(output, "data.repositoryOwner.repositories.nodes")
        local repos = resp.data.repositoryOwner.repositories.nodes
        if #repos == 0 then
          utils.error(string.format("There are no matching repositories for %s.", login))
          return
        end

        for _, repo in ipairs(repos) do
          local entry, entry_str = entry_maker.gen_from_repo(repo)

          if entry ~= nil and entry_str ~= nil then
            formatted_repos[fzf.utils.strip_ansi_coloring(entry_str)] = entry
            fzf_cb(entry_str)
          end
        end
      end
    end,
    cb = function()
      fzf_cb()
    end,
  }
end

return M
