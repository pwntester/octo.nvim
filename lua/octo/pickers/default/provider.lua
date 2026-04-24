---@diagnostic disable
---Picker that uses vim.ui.select
local notify = require "octo.notify"
local utils = require "octo.utils"
local gh = require "octo.gh"
local queries = require "octo.gh.queries"
local octo_config = require "octo.config"

local M = {}

-- Helper: render a label item as preview lines (name, color, description)
local function label_preview(label)
  local lines = {}
  table.insert(lines, "Name:  " .. (label.name or ""))
  table.insert(lines, "Color: #" .. (label.color or ""))
  if not utils.is_blank(label.description) then
    table.insert(lines, "")
    table.insert(lines, label.description)
  end
  return lines
end

-- Helper: render a user item as preview lines (login, name, bio)
local function user_preview(user)
  local lines = {}
  table.insert(lines, "Login: " .. (user.login or ""))
  if not utils.is_blank(user.name) then
    table.insert(lines, "Name:  " .. user.name)
  end
  if not utils.is_blank(user.bio) then
    table.insert(lines, "")
    for _, line in ipairs(vim.split(user.bio, "\n")) do
      table.insert(lines, line)
    end
  end
  return lines
end

function M.actions(flattened_actions)
  vim.ui.select(flattened_actions, {
    prompt = "Select Action:",
    format_item = function(item)
      return item.object .. " " .. item.name
    end,
  }, function(choice)
    if not choice then
      notify.error "No action selected"
      return
    end

    choice.fun()
  end)
end

---@param opts? { repo: string, cb: function }
function M.discussions(opts)
  opts = opts or {}
  if utils.is_blank(opts.repo) then
    opts.repo = utils.get_remote_name()
  end

  local cfg = octo_config.values
  local callback = opts.cb
    or function(selection)
      utils.get("discussion", selection.number, selection.repository.nameWithOwner)
    end

  local owner, name = utils.split_repo(opts.repo)

  local order_by = cfg.discussions.order_by

  gh.api.graphql {
    query = queries.discussions,
    F = {
      owner = owner,
      name = name,
      states = { "OPEN" },
      orderBy = order_by.field,
      direction = order_by.direction,
    },
    paginate = true,
    jq = ".data.repository.discussions.nodes",
    opts = {
      cb = gh.create_callback {
        success = function(output)
          local discussions = utils.get_flatten_pages(output)

          vim.ui.select(discussions, {
            prompt = "Select Discussion:",
            format_item = function(item)
              return item.title
            end,
          }, function(choice)
            if not choice then
              notify.error "No discussion selected"
              return
            end
            callback(choice)
          end)
        end,
      },
    },
  }
end

local function open_buffer(selection)
  utils.get("issue", selection.number, selection.repository.nameWithOwner)
end

---@param opts? { repo: string, states: string[], cb: function }
function M.issues(opts)
  opts = opts or {}
  opts.states = opts.states or { "OPEN" }
  opts.cb = opts.cb or open_buffer

  local repo = utils.pop_key(opts, "repo")
  if utils.is_blank(repo) then
    repo = utils.get_remote_name()
  end

  local cfg = octo_config.values

  local owner, name = utils.split_repo(repo)

  local callback = utils.pop_key(opts, "cb") or open_buffer

  notify.info "Fetching issues (this may take a while)..."
  gh.api.graphql {
    query = queries.issues,
    F = {
      owner = owner,
      name = name,
      filter_by = opts,
      order_by = cfg.issues.order_by,
    },
    paginate = true,
    jq = ".",
    opts = {
      cb = gh.create_callback {
        success = function(data)
          local resp = utils.aggregate_pages(data, "data.repository.issues.nodes")
          local issues = resp.data.repository.issues.nodes

          if #issues == 0 then
            notify.error "No issues found"
            return
          end

          vim.ui.select(issues, {
            prompt = "Select Issue:",
            format_item = function(item)
              return string.format("#%d %s [%s]", item.number, item.title, item.state)
            end,
          }, function(choice)
            if not choice then
              notify.error "No issue selected"
              return
            end
            callback(choice)
          end)
        end,
      },
    },
  }
end

---@param opts? {
---   repo: string,
---   states: string[],
---   baseRefName?: string,
---   headRefName?: string,
---   labels?: string[],
---   states?: string[],
---   cb: function,
--- }
function M.pull_requests(opts)
  opts = opts or {}

  local owner, name = utils.split_repo(opts.repo or utils.get_remote_name())
  utils.info "Fetching pull requests (this may take a while) ..."
  gh.api.graphql {
    query = queries.pull_requests,
    F = {
      owner = owner,
      name = name,
      base_ref_name = opts.baseRefName,
      head_ref_name = opts.headRefName,
      labels = opts.labels,
      states = opts.states or { "OPEN" },
      order_by = octo_config.values.pull_requests.order_by,
    },
    jq = ".",
    paginate = true,
    opts = {
      cb = gh.create_callback {
        success = function(data)
          local resp = utils.aggregate_pages(data, "data.repository.pullRequests.nodes")
          local pull_requests = resp.data.repository.pullRequests.nodes

          vim.ui.select(pull_requests, {
            prompt = "Select Pull Request:",
            format_item = function(item)
              return string.format("#%d %s [%s]", item.number, item.title, item.state)
            end,
          }, function(choice)
            if not choice then
              notify.error "No pull request selected"
              return
            end
            utils.get("pull_request", choice.number, choice.repository.nameWithOwner)
          end)
        end,
      },
    },
  }
end

---@param opts? { repo?: string, cb?: function }
M.releases = function(opts)
  opts = opts or {}
  opts.repo = opts.repo or utils.get_remote_name()

  local callback = opts.cb or function(release)
    utils.get("release", release.tagName, opts.repo)
  end

  gh.release.list {
    repo = opts.repo,
    json = "name,tagName,createdAt",
    opts = {
      cb = gh.create_callback {
        success = function(output)
          local releases = vim.json.decode(output)

          if #releases == 0 then
            local msg = "No releases found"
            if opts.repo then
              msg = msg .. " for " .. opts.repo
            else
              msg = msg .. " in the current repository"
            end
            notify.error(msg)
            return
          end

          vim.ui.select(releases, {
            prompt = "Select Release:",
            format_item = function(release)
              return string.format("%s (%s)", release.name or release.tagName, release.tagName)
            end,
          }, function(release)
            if not release then
              notify.error "No release selected"
              return
            end

            callback(release)
          end)
        end,
      },
    },
  }
end

---@param edits octo.UserContentEdit[]
function M.comment_edits(edits)
  vim.ui.select(edits, {
    prompt = "Comment Edit History:",
    format_item = function(edit)
      local editor = edit.editor and edit.editor.login or "unknown"
      local utc_ts = utils.parse_utc_date(edit.editedAt)
      local tz_offset = os.difftime(os.time(), os.time(os.date "!*t" --[[@as osdateparam]]))
      local abs_time = os.date("%b %d %H:%M", utc_ts + tz_offset) --[[@as string]]
      return string.format("%s  %s (%s)", editor, abs_time, utils.format_date(edit.editedAt))
    end,
    preview_item = function(edit)
      if not utils.is_blank(edit.diff) then
        return vim.split(edit.diff:gsub("\r\n", "\n"):gsub("\r", "\n"), "\n")
      end
      return { "(no diff available)" }
    end,
  }, function(choice)
    if not choice then
      return
    end
    if not utils.is_blank(choice.diff) then
      -- show the diff in a scratch buffer
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(choice.diff:gsub("\r\n", "\n"):gsub("\r", "\n"), "\n"))
      vim.api.nvim_set_option_value("filetype", "diff", { scope = "local", buf = bufnr })
      vim.api.nvim_set_option_value("modifiable", false, { scope = "local", buf = bufnr })
      vim.cmd "split"
      vim.api.nvim_win_set_buf(0, bufnr)
    else
      utils.info "No diff available for this edit"
    end
  end)
end

---@param templates table[]
---@param cb function
function M.issue_templates(templates, cb)
  vim.ui.select(templates, {
    prompt = "Select Issue Template:",
    format_item = function(item)
      return item.name or item.title or "(unnamed)"
    end,
    preview_item = function(item)
      local lines = {}
      if item.about or item.description then
        local desc = item.about or item.description
        for _, line in ipairs(vim.split(desc, "\n")) do
          table.insert(lines, line)
        end
        table.insert(lines, "")
        table.insert(lines, string.rep("─", 40))
        table.insert(lines, "")
      end
      if not utils.is_blank(item.body) then
        for _, line in ipairs(vim.split(item.body, "\n")) do
          table.insert(lines, line)
        end
      end
      return #lines > 0 and lines or { "(empty template)" }
    end,
  }, function(choice)
    if not choice then
      notify.error "No template selected"
      return
    end
    cb(choice)
  end)
end

---@param threads table[]
function M.pending_threads(threads)
  vim.ui.select(threads, {
    prompt = "Select Pending Thread:",
    format_item = function(thread)
      local start_line = not utils.is_blank(thread.startLine) and thread.startLine or thread.line
      local end_line = thread.line
      if start_line == end_line then
        return string.format("%s:%d", thread.path, end_line)
      else
        return string.format("%s:%d-%d", thread.path, start_line, end_line)
      end
    end,
    preview_item = function(thread)
      local lines = {}
      local start_line = not utils.is_blank(thread.startLine) and thread.startLine or thread.line
      table.insert(lines, string.format("File:  %s", thread.path or ""))
      table.insert(lines, string.format("Lines: %d-%d", start_line, thread.line or start_line))
      if thread.diffSide then
        table.insert(lines, string.format("Side:  %s", thread.diffSide))
      end
      table.insert(lines, "")
      -- render comments if available
      local comments = thread.comments and thread.comments.nodes or {}
      for i, comment in ipairs(comments) do
        local author = comment.author and comment.author.login or "unknown"
        table.insert(lines, string.format("[%d] %s:", i, author))
        if comment.body then
          for _, line in ipairs(vim.split(comment.body:gsub("\r\n", "\n"):gsub("\r", "\n"), "\n")) do
            table.insert(lines, "  " .. line)
          end
        end
        table.insert(lines, "")
      end
      return #lines > 0 and lines or { "(no content)" }
    end,
  }, function(choice)
    if not choice then
      return
    end
    local reviews = require "octo.reviews"
    reviews.jump_to_pending_review_thread(choice)
  end)
end

---@param workflow_runs table[]
---@param title? string
---@param on_select_cb function
function M.workflow_runs(workflow_runs, title, on_select_cb)
  vim.ui.select(workflow_runs, {
    prompt = title or "Select Workflow Run:",
    format_item = function(run)
      local status = run.status or "unknown"
      local conclusion = run.conclusion and (" [" .. run.conclusion .. "]") or ""
      local branch = run.head_branch or run.headBranch or ""
      return string.format("%s (%s%s) %s", run.name or run.display_title or "Run", status, conclusion, branch)
    end,
    preview_item = function(run)
      local lines = {}
      table.insert(lines, string.format("Name:        %s", run.name or run.display_title or ""))
      table.insert(lines, string.format("Status:      %s", run.status or ""))
      table.insert(lines, string.format("Conclusion:  %s", run.conclusion or "in progress"))
      table.insert(lines, string.format("Branch:      %s", run.head_branch or run.headBranch or ""))
      table.insert(lines, string.format("Event:       %s", run.event or ""))
      if run.head_commit then
        table.insert(lines, string.format("Commit:      %s", (run.head_commit.id or run.head_sha or ""):sub(1, 7)))
        if run.head_commit.message then
          table.insert(lines, string.format("Message:     %s", run.head_commit.message:match "^[^\n]+"))
        end
      elseif run.head_sha then
        table.insert(lines, string.format("SHA:         %s", run.head_sha:sub(1, 7)))
      end
      if run.created_at or run.createdAt then
        table.insert(lines, string.format("Created:     %s", utils.format_date(run.created_at or run.createdAt)))
      end
      if run.updated_at or run.updatedAt then
        table.insert(lines, string.format("Updated:     %s", utils.format_date(run.updated_at or run.updatedAt)))
      end
      if run.html_url or run.url then
        table.insert(lines, "")
        table.insert(lines, string.format("URL: %s", run.html_url or run.url))
      end
      return lines
    end,
  }, function(choice)
    if not choice then
      return
    end
    on_select_cb(choice)
  end)
end

---@param cb function
function M.project_cards_v2(cb)
  local buffer = utils.get_current_buffer()
  if not buffer then
    return
  end

  local obj = buffer:isIssue() and buffer:issue() or buffer:pullRequest()
  local cards = obj and obj.projectItems
  if not cards or #cards.nodes == 0 then
    utils.error "Can't find any project v2 cards"
    return
  end

  if #cards.nodes == 1 then
    local node = cards.nodes[1]
    cb(node.project.id, node.id)
  else
    utils.error "Multiple project cards are not supported yet"
  end
end

---@param cb function
function M.project_columns_v2(cb)
  local buffer = utils.get_current_buffer()
  if not buffer then
    return
  end

  local parser = require "octo.gh.parser"

  gh.api.graphql {
    query = queries.projects_v2,
    F = {
      owner = buffer.owner,
      name = buffer.name,
      viewer = vim.g.octo_viewer,
    },
    opts = {
      cb = function(output)
        if not output then
          return
        end

        local resp = vim.json.decode(output)
        local results = parser.projects(resp)

        if #results == 0 then
          utils.error "No projects found"
          return
        end

        vim.ui.select(results, {
          prompt = "Select Project:",
          format_item = function(project)
            return string.format("#%d %s", project.number, project.title)
          end,
        }, function(project)
          if not project then
            return
          end

          vim.ui.select(project.columns.options, {
            prompt = "Select Field Value:",
            format_item = function(item)
              return item.name
            end,
          }, function(value)
            if not value then
              return
            end
            cb(project.id, project.columns.id, value.id)
          end)
        end)
      end,
    },
  }
end

---@param opts? { repo?: string, cb?: function }
function M.labels(opts)
  opts = opts or {}
  local cb = opts.cb
  local repo = opts.repo or utils.get_remote_name()
  local owner, name = utils.split_repo(repo)

  gh.api.graphql {
    query = queries.labels,
    F = { owner = owner, name = name },
    jq = ".data.repository.labels.nodes",
    opts = {
      cb = gh.create_callback {
        success = function(output)
          local label_list = vim.json.decode(output)

          if #label_list == 0 then
            notify.error "No labels found"
            return
          end

          vim.ui.select(label_list, {
            prompt = "Select Label(s):",
            format_item = function(label)
              return label.name
            end,
            preview_item = label_preview,
          }, function(choice)
            if not choice then
              return
            end
            cb { choice }
          end)
        end,
      },
    },
  }
end

---@param opts? { cb?: function }
function M.assigned_labels(opts)
  opts = opts or {}
  local cb = opts.cb

  local buffer = utils.get_current_buffer()
  if not buffer then
    return
  end

  local query, key
  if buffer:isIssue() then
    query = queries.issue_labels
    key = "issue"
  elseif buffer:isPullRequest() then
    query = queries.pull_request_labels
    key = "pullRequest"
  elseif buffer:isDiscussion() then
    query = queries.discussion_labels
    key = "discussion"
  else
    utils.error "Not in an issue, PR, or discussion buffer"
    return
  end

  local F = { owner = buffer.owner, name = buffer.name, number = buffer.number }

  gh.api.graphql {
    query = query,
    F = F,
    jq = ".data.repository." .. key .. ".labels.nodes",
    opts = {
      cb = gh.create_callback {
        success = function(output)
          local label_list = vim.json.decode(output)

          if #label_list == 0 then
            notify.error "No assigned labels found"
            return
          end

          vim.ui.select(label_list, {
            prompt = "Select Label(s):",
            format_item = function(label)
              return label.name
            end,
            preview_item = label_preview,
          }, function(choice)
            if not choice then
              return
            end
            cb { choice }
          end)
        end,
      },
    },
  }
end

---@param cb function
function M.assignees(cb)
  local buffer = utils.get_current_buffer()
  if not buffer then
    return
  end

  local query, key
  if buffer:isIssue() then
    query = queries.issue_assignees
    key = "issue"
  elseif buffer:isPullRequest() then
    query = queries.pull_request_assignees
    key = "pullRequest"
  else
    utils.error "Not in an issue or PR buffer"
    return
  end

  local F = { owner = buffer.owner, name = buffer.name, number = buffer.number }

  gh.api.graphql {
    query = query,
    F = F,
    paginate = true,
    opts = {
      cb = function(output, stderr)
        if stderr and not utils.is_blank(stderr) then
          utils.error(stderr)
          return
        end
        local resp = vim.json.decode(output)
        local assignees = resp.data.repository[key].assignees.nodes

        if #assignees == 0 then
          notify.error "No assignees found"
          return
        end

        vim.ui.select(assignees, {
          prompt = "Select Assignee:",
          format_item = function(user)
            if not utils.is_blank(user.name) then
              return string.format("%s (%s)", user.login, user.name)
            end
            return user.login
          end,
          preview_item = user_preview,
        }, function(choice)
          if not choice then
            return
          end
          cb(choice.id)
        end)
      end,
    },
  }
end

---@param opts? { repo?: string }
function M.milestones(opts)
  opts = opts or {}
  if opts.cb == nil then
    utils.error "Callback action on milestone is required"
    return
  end

  local repo = opts.repo or utils.get_remote_name()
  local owner, name = utils.split_repo(repo --[[@as string]])

  gh.api.graphql {
    query = queries.open_milestones,
    fields = {
      owner = owner,
      name = name,
      n_milestones = 25,
    },
    opts = {
      cb = function(output, stderr)
        if stderr and not utils.is_blank(stderr) then
          utils.error(stderr)
          return
        end

        local resp = vim.json.decode(output)
        local nodes = resp.data.repository.milestones.nodes

        if #nodes == 0 then
          utils.error(string.format("There are no open milestones in %s.", repo))
          return
        end

        vim.ui.select(nodes, {
          prompt = "Select Milestone:",
          format_item = function(milestone)
            if not utils.is_blank(milestone.description) then
              return string.format("%s — %s", milestone.title, milestone.description)
            end
            return milestone.title
          end,
          preview_item = function(milestone)
            local lines = {}
            table.insert(lines, "Title: " .. (milestone.title or ""))
            if not utils.is_blank(milestone.description) then
              table.insert(lines, "")
              for _, line in ipairs(vim.split(milestone.description, "\n")) do
                table.insert(lines, line)
              end
            end
            if not utils.is_blank(milestone.dueOn) then
              table.insert(lines, "")
              table.insert(lines, "Due: " .. utils.format_date(milestone.dueOn))
            end
            if not utils.is_blank(milestone.url) then
              table.insert(lines, "")
              table.insert(lines, "URL: " .. milestone.url)
            end
            return #lines > 0 and lines or { milestone.title or "(unnamed)" }
          end,
        }, function(choice)
          if not choice then
            return
          end
          opts.cb(choice)
        end)
      end,
    },
  }
end

---@param cb function
function M.users(cb)
  local cfg = octo_config.values

  local function pick_user(user_list)
    vim.ui.select(user_list, {
      prompt = "Select User:",
      format_item = function(user)
        if user.teams then
          return string.format("%s (%d teams)", user.login, #user.teams)
        elseif not utils.is_blank(user.name) then
          return string.format("%s (%s)", user.login, user.name)
        end
        return user.login
      end,
      preview_item = function(user)
        if user.teams then
          local lines = { "Organization: " .. user.login, "", "Teams:" }
          for _, team in ipairs(user.teams) do
            table.insert(lines, "  • " .. (team.name or team.slug or team.id or ""))
          end
          return lines
        end
        return user_preview(user)
      end,
    }, function(choice)
      if not choice then
        return
      end
      if choice.teams then
        -- organization — pick a team
        vim.ui.select(choice.teams, {
          prompt = "Select Team:",
          format_item = function(team)
            return team.name or team.slug or team.id
          end,
          preview_item = function(team)
            local lines = {}
            table.insert(lines, "Name: " .. (team.name or ""))
            if team.slug then
              table.insert(lines, "Slug: " .. team.slug)
            end
            if not utils.is_blank(team.description) then
              table.insert(lines, "")
              table.insert(lines, team.description)
            end
            return #lines > 0 and lines or { team.name or team.id or "" }
          end,
        }, function(team)
          if not team then
            return
          end
          cb(team.id)
        end)
      else
        cb(choice.id)
      end
    end)
  end

  if cfg.users == "search" then
    vim.ui.input({ prompt = "Search users: " }, function(prompt)
      if not prompt or utils.is_blank(prompt) then
        return
      end

      gh.api.graphql {
        query = queries.users,
        F = { prompt = prompt },
        paginate = true,
        opts = {
          cb = gh.create_callback {
            success = function(output)
              local users = {}
              local orgs = {}
              local responses = utils.get_pages(output)
              for _, resp in ipairs(responses) do
                for _, user in ipairs(resp.data.search.nodes) do
                  if not user.teams then
                    if not vim.tbl_contains(vim.tbl_keys(users), user.login) then
                      users[user.login] = { id = user.id, login = user.login, name = user.name }
                    end
                  elseif user.teams and user.teams.totalCount > 0 then
                    if not vim.tbl_contains(vim.tbl_keys(orgs), user.login) then
                      orgs[user.login] = { id = user.id, login = user.login, teams = user.teams.nodes }
                    else
                      vim.list_extend(orgs[user.login].teams, user.teams.nodes)
                    end
                  end
                end
              end

              local results = {}
              for _, user in pairs(users) do
                table.insert(results, user)
              end
              for _, org in pairs(orgs) do
                table.insert(results, org)
              end

              if #results == 0 then
                notify.error "No users found"
                return
              end

              pick_user(results)
            end,
          },
        },
      }
    end)
  else
    local query_name = cfg.users == "assignable" and "assignable_users" or "mentionable_users"
    local node_name = cfg.users == "assignable" and "assignableUsers" or "mentionableUsers"

    local repo = utils.get_remote_name()
    local owner, name = utils.split_repo(repo)

    gh.api.graphql {
      query = queries[query_name],
      f = { owner = owner, name = name },
      paginate = true,
      jq = ".data.repository." .. node_name .. ".nodes",
      opts = {
        cb = gh.create_callback {
          success = function(output)
            local user_list = utils.get_flatten_pages(output)

            if #user_list == 0 then
              notify.error "No users found"
              return
            end

            pick_user(user_list)
          end,
        },
      },
    }
  end
end

---@param opts? { login?: string }
function M.repos(opts)
  opts = opts or {}

  utils.info "Fetching repositories (this may take a while) ..."
  gh.api.graphql {
    query = queries.repos,
    f = { login = opts.login },
    paginate = true,
    jq = ".data.repositoryOwner.repositories.nodes",
    opts = {
      cb = gh.create_callback {
        success = function(output)
          local repos = utils.get_flatten_pages(output)

          if #repos == 0 then
            utils.error(string.format("There are no matching repositories for %s.", opts.login or "owner"))
            return
          end

          vim.ui.select(repos, {
            prompt = "Select Repository:",
            format_item = function(repo)
              return string.format("%s ⑂%d ★%d", repo.nameWithOwner, repo.forkCount, repo.stargazerCount)
            end,
          }, function(choice)
            if not choice then
              return
            end
            utils.get("repo", nil, choice.nameWithOwner)
          end)
        end,
      },
    },
  }
end

---@param opts {repo: string, number: integer}
function M.changed_files(opts)
  gh.api.get {
    "/repos/{repo}/pulls/{number}/files",
    format = { repo = opts.repo, number = opts.number },
    paginate = true,
    opts = {
      cb = gh.create_callback {
        success = function(output)
          local files = vim.json.decode(output)

          if #files == 0 then
            notify.error "No changed files found"
            return
          end

          -- add `file` field for snacks auto-preview and quickfix integration
          for _, f in ipairs(files) do
            if vim.fn.filereadable(f.filename) == 1 then
              f.file = f.filename
            end
          end

          vim.ui.select(files, {
            prompt = "Select Changed File:",
            format_item = function(file)
              return string.format("%s +%d -%d", file.filename, file.additions, file.deletions)
            end,
            preview_item = function(file)
              if not utils.is_blank(file.patch) then
                return vim.split(file.patch:gsub("\r\n", "\n"):gsub("\r", "\n"), "\n")
              end
              return { string.format("-- %s (no patch available)", file.filename) }
            end,
          }, function(choice)
            if not choice then
              return
            end
            -- open the file in a split if it exists locally, otherwise show patch
            local filename = choice.filename
            if vim.fn.filereadable(filename) == 1 then
              vim.cmd("split " .. vim.fn.fnameescape(filename))
            else
              -- show the patch in a scratch buffer
              local bufnr = vim.api.nvim_create_buf(false, true)
              local patch = choice.patch or ("-- No patch available for " .. filename)
              vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(patch, "\n"))
              vim.api.nvim_set_option_value("filetype", "diff", { scope = "local", buf = bufnr })
              vim.api.nvim_set_option_value("modifiable", false, { scope = "local", buf = bufnr })
              vim.cmd "split"
              vim.api.nvim_win_set_buf(0, bufnr)
            end
          end)
        end,
      },
    },
  }
end

---@param opts {repo: string, number: integer}
function M.commits(opts)
  -- TODO: graphql
  gh.api.get {
    "/repos/{repo}/pulls/{number}/commits",
    format = { repo = opts.repo, number = opts.number },
    paginate = true,
    opts = {
      cb = gh.create_callback {
        success = function(output)
          local commits = vim.json.decode(output)

          if #commits == 0 then
            notify.error "No commits found"
            return
          end

          vim.ui.select(commits, {
            prompt = "Select Commit:",
            format_item = function(commit)
              local sha = commit.sha:sub(1, 7)
              local author = commit.commit.author and commit.commit.author.name or "unknown"
              local msg = commit.commit.message:match "^[^\n]+" or commit.commit.message
              return string.format("%s %s — %s", sha, author, msg)
            end,
            preview_item = function(commit)
              local lines = {}
              table.insert(lines, "commit " .. commit.sha)
              local author = commit.commit.author
              if author then
                table.insert(lines, "Author: " .. (author.name or "") .. " <" .. (author.email or "") .. ">")
                table.insert(lines, "Date:   " .. (author.date or ""))
              end
              table.insert(lines, "")
              for _, line in ipairs(vim.split(commit.commit.message:gsub("\r\n", "\n"):gsub("\r", "\n"), "\n")) do
                table.insert(lines, "    " .. line)
              end
              return lines
            end,
          }, function(choice)
            if not choice then
              return
            end
            -- Show commit diff in a scratch buffer
            local bufnr = vim.api.nvim_create_buf(false, true)
            local lines = {
              "commit " .. choice.sha,
              "Author: " .. (choice.commit.author and choice.commit.author.name or "unknown"),
              "Date:   " .. (choice.commit.author and choice.commit.author.date or "unknown"),
              "",
            }
            for _, line in ipairs(vim.split(choice.commit.message, "\n")) do
              table.insert(lines, "    " .. line)
            end
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
            vim.api.nvim_set_option_value("filetype", "git", { scope = "local", buf = bufnr })
            vim.api.nvim_set_option_value("modifiable", false, { scope = "local", buf = bufnr })
            vim.cmd "split"
            vim.api.nvim_win_set_buf(0, bufnr)
          end)
        end,
      },
    },
  }
end

---@param current_review Review
---@param callback fun(right: Rev, left: Rev): nil
function M.review_commits(current_review, callback)
  -- TODO: graphql
  gh.api.get {
    "/repos/{repo}/pulls/{number}/commits",
    format = { repo = current_review.pull_request.repo, number = current_review.pull_request.number },
    paginate = true,
    opts = {
      cb = gh.create_callback {
        success = function(output)
          local commits = vim.json.decode(output)

          -- add a synthetic entry to represent the entire pull request
          table.insert(commits, {
            sha = current_review.pull_request.right.commit,
            commit = {
              message = "[[ENTIRE PULL REQUEST]]",
              author = { name = "", email = "", date = "" },
            },
            parents = { { sha = current_review.pull_request.left.commit } },
          })

          vim.ui.select(commits, {
            prompt = "Select Commit to Review:",
            format_item = function(commit)
              local sha = commit.sha:sub(1, 7)
              local msg = commit.commit.message:match "^[^\n]+" or commit.commit.message
              local author = commit.commit.author and commit.commit.author.name or ""
              if author ~= "" then
                return string.format("%s %s — %s", sha, author, msg)
              end
              return string.format("%s %s", sha, msg)
            end,
            preview_item = function(commit)
              local lines = {}
              table.insert(lines, "commit " .. commit.sha)
              local author = commit.commit.author
              if author and not utils.is_blank(author.name) then
                table.insert(lines, "Author: " .. (author.name or "") .. " <" .. (author.email or "") .. ">")
                table.insert(lines, "Date:   " .. (author.date or ""))
              end
              table.insert(lines, "")
              for _, line in ipairs(vim.split(commit.commit.message:gsub("\r\n", "\n"):gsub("\r", "\n"), "\n")) do
                table.insert(lines, "    " .. line)
              end
              return lines
            end,
          }, function(choice)
            if not choice then
              return
            end
            local right = choice.sha
            local left = choice.parents and choice.parents[1] and choice.parents[1].sha or nil
            callback(right, left)
          end)
        end,
      },
    },
  }
end

---@param opts? { repo?: string, all?: boolean, since?: string }
function M.notifications(opts)
  opts = opts or {}
  opts.all = opts.all or false

  local notifications = require "octo.notifications"

  local endpoint = "/notifications"
  if opts.repo then
    local owner, name = utils.split_repo(opts.repo)
    endpoint = string.format("/repos/%s/%s/notifications", owner, name)
  end

  gh.api.get {
    endpoint,
    paginate = true,
    F = {
      all = opts.all,
      since = opts.since,
    },
    opts = {
      cb = gh.create_callback {
        success = function(output)
          local resp = vim.json.decode(output)

          if #resp == 0 then
            utils.info "There are no notifications"
            return
          end

          vim.ui.select(resp, {
            prompt = opts.repo and string.format("%s Notifications:", opts.repo) or "GitHub Notifications:",
            format_item = function(notif)
              local subject = notif.subject and notif.subject.title or "(no title)"
              local kind = notif.subject and notif.subject.type or "Unknown"
              local repo = notif.repository and notif.repository.full_name or ""
              local unread = notif.unread and "[unread] " or ""
              if opts.repo then
                return string.format("%s%s (%s)", unread, subject, kind)
              else
                return string.format("%s%s (%s) — %s", unread, subject, kind, repo)
              end
            end,
          }, function(choice)
            if not choice then
              return
            end

            local kind = choice.subject and choice.subject.type or nil
            local url = choice.subject and choice.subject.url or nil
            local number = url and url:match "%d+$" or nil
            local repo_name = choice.repository and choice.repository.full_name or nil

            -- Mark as read when opening
            if choice.id then
              notifications.request_read_notification(choice.id)
            end

            if kind == "Issue" and number and repo_name then
              utils.get("issue", tonumber(number), repo_name)
            elseif kind == "PullRequest" and number and repo_name then
              utils.get("pull_request", tonumber(number), repo_name)
            elseif kind == "Discussion" and number and repo_name then
              utils.get("discussion", tonumber(number), repo_name)
            else
              -- fallback: open in browser
              local html_url = choice.subject and choice.subject.url
              if html_url then
                -- convert API URL to web URL
                local web_url = html_url
                  :gsub("api%.github%.com/repos/", "github.com/")
                  :gsub("/pulls/", "/pull/")
                  :gsub("/issues/", "/issues/")
                vim.ui.open(web_url)
              end
            end
          end)
        end,
      },
    },
  }
end

---@param opts? { public?: boolean, secret?: boolean }
function M.gists(opts)
  opts = opts or {}

  local privacy
  if opts.public then
    privacy = "PUBLIC"
  elseif opts.secret then
    privacy = "SECRET"
  else
    privacy = "ALL"
  end

  gh.api.graphql {
    query = queries.gists,
    F = { privacy = privacy },
    paginate = true,
    jq = ".",
    opts = {
      cb = function(output, stderr)
        if stderr and not utils.is_blank(stderr) then
          utils.error(stderr)
          return
        end
        if not output then
          return
        end

        local resp = utils.aggregate_pages(output, "data.viewer.gists.nodes")
        local gists = resp.data.viewer.gists.nodes

        if #gists == 0 then
          notify.error "No gists found"
          return
        end

        vim.ui.select(gists, {
          prompt = "Select Gist:",
          format_item = function(gist)
            local desc = not utils.is_blank(gist.description) and gist.description or nil
            -- pick the first file name as a hint
            local first_file = nil
            if gist.files and #gist.files > 0 then
              first_file = gist.files[1].name
            end
            if desc then
              return desc
            elseif first_file then
              return first_file
            else
              return gist.name or gist.id or "(unnamed gist)"
            end
          end,
          preview_item = function(gist)
            local lines = {}
            if not utils.is_blank(gist.description) then
              table.insert(lines, "Description: " .. gist.description)
              table.insert(lines, "")
            end
            if gist.files and #gist.files > 0 then
              -- show the first file's content; note all files in the gist
              local first = gist.files[1]
              if #gist.files > 1 then
                local names = {}
                for _, f in ipairs(gist.files) do
                  table.insert(names, f.name or "?")
                end
                table.insert(lines, "Files: " .. table.concat(names, ", "))
                table.insert(lines, "")
              end
              if first.text then
                for _, line in ipairs(vim.split(first.text:gsub("\r\n", "\n"):gsub("\r", "\n"), "\n")) do
                  table.insert(lines, line)
                end
              else
                table.insert(lines, "(binary or empty file)")
              end
            end
            return #lines > 0 and lines or { "(empty gist)" }
          end,
        }, function(choice)
          if not choice then
            return
          end

          -- open each gist file in a scratch buffer
          if choice.files and #choice.files > 0 then
            for _, file in ipairs(choice.files) do
              local bufnr = vim.api.nvim_create_buf(true, true)
              vim.api.nvim_buf_set_name(bufnr, file.name or "gist")
              if file.text then
                vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(file.text, "\n"))
              end
              vim.cmd "split"
              vim.api.nvim_win_set_buf(0, bufnr)
              vim.cmd "filetype detect"
            end
          else
            notify.error "Gist has no files"
          end
        end)
      end,
    },
  }
end

---@param opts? { type?: string, prompt?: string|string[], repo?: string }
function M.search(opts)
  opts = opts or {}

  local search_type = opts.type or "ISSUE"

  -- If type not specified, ask the user
  if not opts.type then
    vim.ui.select({ "ISSUE", "DISCUSSION", "REPOSITORY" }, {
      prompt = "Search type:",
      format_item = function(t)
        if t == "ISSUE" then
          return "Issues & Pull Requests"
        elseif t == "DISCUSSION" then
          return "Discussions"
        else
          return "Repositories"
        end
      end,
    }, function(choice)
      if not choice then
        return
      end
      opts.type = choice
      M.search(opts)
    end)
    return
  end

  local prompt_list = opts.prompt
  if type(prompt_list) == "string" then
    prompt_list = { prompt_list }
  end

  local function do_search(query_str)
    local full_prompt = query_str or ""
    if prompt_list then
      for _, p in ipairs(prompt_list) do
        full_prompt = p .. " " .. full_prompt
      end
    end

    if utils.is_blank(full_prompt) then
      notify.error "Search query is empty"
      return
    end

    gh.api.graphql {
      query = queries.search,
      f = { prompt = vim.trim(full_prompt), type = search_type },
      F = { last = 50 },
      jq = ".data.search.nodes",
      opts = {
        cb = gh.create_callback {
          success = function(output)
            local results = vim.json.decode(output)

            if #results == 0 then
              notify.error "No results found"
              return
            end

            vim.ui.select(results, {
              prompt = string.format("Search results (%s):", search_type),
              format_item = function(item)
                local typename = item.__typename or ""
                if typename == "Issue" or typename == "PullRequest" then
                  local repo = item.repository and item.repository.nameWithOwner or ""
                  return string.format("#%d %s [%s] %s", item.number, item.title, item.state or typename, repo)
                elseif typename == "Discussion" then
                  return string.format("#%d %s", item.number, item.title)
                elseif typename == "Repository" then
                  return string.format(
                    "%s ⑂%d ★%d",
                    item.nameWithOwner,
                    item.forkCount or 0,
                    item.stargazerCount or 0
                  )
                else
                  return item.title or item.nameWithOwner or tostring(item)
                end
              end,
            }, function(choice)
              if not choice then
                return
              end

              if opts.cb then
                opts.cb(choice)
                return
              end

              local typename = choice.__typename or ""
              if typename == "Issue" then
                utils.get("issue", choice.number, choice.repository.nameWithOwner)
              elseif typename == "PullRequest" then
                utils.get("pull_request", choice.number, choice.repository.nameWithOwner)
              elseif typename == "Discussion" then
                utils.get("discussion", choice.number, choice.repository.nameWithOwner)
              elseif typename == "Repository" then
                utils.get("repo", nil, choice.nameWithOwner)
              end
            end)
          end,
        },
      },
    }
  end

  if prompt_list and #prompt_list > 0 then
    do_search(nil)
  else
    vim.ui.input({ prompt = "Search query: " }, function(input)
      if input == nil then
        return
      end
      do_search(input)
    end)
  end
end

---@type octo.PickerModule
M.picker = {
  actions = M.actions,
  assigned_labels = M.assigned_labels,
  assignees = M.assignees,
  changed_files = M.changed_files,
  comment_edits = M.comment_edits,
  commits = M.commits,
  discussions = M.discussions,
  gists = M.gists,
  issue_templates = M.issue_templates,
  issues = M.issues,
  labels = M.labels,
  milestones = M.milestones,
  notifications = M.notifications,
  pending_threads = M.pending_threads,
  project_cards_v2 = M.project_cards_v2,
  project_columns_v2 = M.project_columns_v2,
  prs = M.pull_requests,
  releases = M.releases,
  repos = M.repos,
  review_commits = M.review_commits,
  search = M.search,
  users = M.users,
  workflow_runs = M.workflow_runs,
}

return M
