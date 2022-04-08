local actions = require "telescope.actions"
local action_state = require "telescope.actions.state"
local action_set = require "telescope.actions.set"
local finders = require "telescope.finders"
local pickers = require "telescope.pickers"
local conf = require("telescope.config").values
local sorters = require "telescope.sorters"
local reviews = require "octo.reviews"
local gh = require "octo.gh"
local utils = require "octo.utils"
local navigation = require "octo.navigation"
local graphql = require "octo.graphql"
local previewers = require "octo.pickers.telescope.previewers"
local entry_maker = require "octo.pickers.telescope.entry_maker"
local host = require "octo.host.provider"

local M = {}

local dropdown_opts = require("telescope.themes").get_dropdown {
  layout_config = {
    width = 0.4,
    height = 15,
  },
  prompt_title = false,
  results_title = false,
  previewer = false,
}

local function get_filter(opts, kind)
  local filter = ""
  local allowed_values = {}
  if kind == "issue" then
    allowed_values = { "since", "createdBy", "assignee", "mentioned", "labels", "milestone", "states" }
  elseif kind == "pull_request" then
    allowed_values = { "baseRefName", "headRefName", "labels", "states" }
  end

  for _, value in pairs(allowed_values) do
    if opts[value] then
      local val
      if #vim.split(opts[value], ",") > 1 then
        -- list
        val = vim.split(opts[value], ",")
      else
        -- string
        val = opts[value]
      end
      val = vim.fn.json_encode(val)
      val = string.gsub(val, '"OPEN"', "OPEN")
      val = string.gsub(val, '"CLOSED"', "CLOSED")
      val = string.gsub(val, '"MERGED"', "MERGED")
      filter = filter .. value .. ":" .. val .. ","
    end
  end

  return filter
end

local function get_repository()
  hostname = utils.get_remote_hostname()
  host:set_provider(hostname)

  return utils.get_repository()
end

local function open(command)
  return function(prompt_bufnr)
    local selection = action_state.get_selected_entry(prompt_bufnr)
    actions.close(prompt_bufnr)
    if command == "default" then
      vim.cmd [[:buffer %]]
    elseif command == "horizontal" then
      vim.cmd [[:sbuffer %]]
    elseif command == "vertical" then
      vim.cmd [[:vert sbuffer %]]
    elseif command == "tab" then
      vim.cmd [[:tab sb %]]
    end
    vim.cmd(
      string.format([[ lua require'octo.utils'.get_%s('%s', '%s') ]], selection.kind, selection.repo, selection.value)
    )
  end
end

local function open_preview_buffer(command)
  return function(prompt_bufnr)
    actions.close(prompt_bufnr)
    local preview_bufnr = require("telescope.state").get_global_key "last_preview_bufnr"
    if command == "default" then
      vim.cmd(string.format(":buffer %d", preview_bufnr))
    elseif command == "horizontal" then
      vim.cmd(string.format(":sbuffer %d", preview_bufnr))
    elseif command == "vertical" then
      vim.cmd(string.format(":vert sbuffer %d", preview_bufnr))
    elseif command == "tab" then
      vim.cmd(string.format(":tab sb %d", preview_bufnr))
    end

    vim.cmd [[stopinsert]]
  end
end

local function open_in_browser()
  return function(prompt_bufnr)
    local entry = action_state.get_selected_entry(prompt_bufnr)
    local number
    local repo = entry.repo
    if entry.kind ~= "repo" then
      number = entry.value
    end
    actions.close(prompt_bufnr)
    navigation.open_in_browser(entry.kind, repo, number)
  end
end

local function copy_url()
  return function(prompt_bufnr)
    local entry = action_state.get_selected_entry(prompt_bufnr)
    local url = entry.obj.url
    vim.fn.setreg("+", url, "c")
    utils.notify("Copied '" .. url .. "' to the system clipboard (+ register)", 1)
  end
end

--
-- ISSUES
--
function M.issues(opts)
  opts = opts or {}
  if not opts.states then
    opts.states = "OPEN"
  end

  if not opts.repo or opts.repo == vim.NIL or type(opts.repo) == 'string' then
    opts.repo = get_repository()
  end
  if not opts.repo then
    utils.notify("Cannot find repo", 2)
    return
  end

  local filter = host.util:get_filter(opts, "issue")
  host:list_issues(
    opts.repo,
    filter,
    function(output, stderr)
      print " "
      if stderr and not utils.is_blank(stderr) then
        utils.notify(stderr, 2)
        return
      elseif not output then
        return
      end

      local issues, max_number = host:process_issues(opts, output)
      pickers.new(opts, {
        finder = finders.new_table {
          results = issues,
          entry_maker = entry_maker.gen_from_issue(max_number),
        },
        sorter = conf.generic_sorter(opts),
        previewer = previewers.issue.new(opts),
        attach_mappings = function(_, map)
          action_set.select:replace(function(prompt_bufnr, type)
            open(type)(prompt_bufnr)
          end)
          map("i", "<c-b>", open_in_browser())
          map("i", "<c-y>", copy_url())
          return true
        end,
      }):find()
    end
  )

  -- local query = graphql("issues_query", opts.repo, filter, { escape = false })
  -- print "Fetching issues (this may take a while) SUPER ..."
  -- print(query)

  -- gh.run {
  --   args = { "api", "graphql", "--paginate", "--jq", ".", "-f", string.format("query=%s", query) },
  --   cb = function(output, stderr)
  --     print " "
  --     if stderr and not utils.is_blank(stderr) then
  --       utils.notify(stderr, 2)
  --     elseif output then


  --       pickers.new(opts, {
  --         finder = finders.new_table {
  --           results = issues,
  --           entry_maker = entry_maker.gen_from_issue(max_number),
  --         },
  --         sorter = conf.generic_sorter(opts),
  --         previewer = previewers.issue.new(opts),
  --         attach_mappings = function(_, map)
  --           action_set.select:replace(function(prompt_bufnr, type)
  --             open(type)(prompt_bufnr)
  --           end)
  --           map("i", "<c-b>", open_in_browser())
  --           map("i", "<c-y>", copy_url())
  --           return true
  --         end,
  --       }):find()
  --     end
  --   end,
  -- }
end

--
-- GISTS
--
local function open_gist(prompt_bufnr)
  local selection = action_state.get_selected_entry(prompt_bufnr)
  local gist = selection.gist
  actions.close(prompt_bufnr)
  for _, file in ipairs(gist.files) do
    local bufnr = vim.api.nvim_create_buf(true, true)
    if file.text then
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(file.text, "\n"))
    else
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, gist.description)
    end
    vim.api.nvim_buf_set_name(bufnr, file.name)
    vim.api.nvim_win_set_buf(0, bufnr)
    vim.api.nvim_buf_call(bufnr, function()
      vim.cmd [[filetype detect]]
    end)
  end
end

function M.gists(opts)
  local privacy
  if opts.public then
    privacy = "PUBLIC"
  elseif opts.secret then
    privacy = "SECRET"
  else
    privacy = "ALL"
  end
  local query = graphql("gists_query", privacy)
  gh.run {
    args = { "api", "graphql", "--paginate", "--jq", ".", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.notify(stderr, 2)
      elseif output then
        local resp = utils.aggregate_pages(output, "data.viewer.gists.nodes")
        local gists = resp.data.viewer.gists.nodes
        opts.preview_title = opts.preview_title or ""
        opts.prompt_title = opts.prompt_title or ""
        opts.results_title = opts.results_title or ""
        pickers.new(opts, {
          finder = finders.new_table {
            results = gists,
            entry_maker = entry_maker.gen_from_gist(),
          },
          previewer = previewers.gist.new(opts),
          sorter = conf.generic_sorter(opts),
          attach_mappings = function(_, map)
            map("i", "<CR>", open_gist)
            return true
          end,
        }):find()
      end
    end,
  }
end

--
-- PULL REQUESTS
--

local function checkout_pull_request()
  return function(prompt_bufnr)
    local selection = action_state.get_selected_entry(prompt_bufnr)
    actions.close(prompt_bufnr)
    local headRefName = selection.pull_request.headRefName
    utils.checkout_pr(headRefName)
  end
end

function M.pull_requests(opts)
  opts = opts or {}
  if not opts.states then
    opts.states = "OPEN"
  end
  local filter = get_filter(opts, "pull_request")

  if not opts.repo or opts.repo == vim.NIL then
    opts.repo = utils.get_remote_name()
  end
  if not opts.repo then
    utils.notify("Cannot find repo", 2)
    return
  end

  local owner, name = utils.split_repo(opts.repo)
  local query = graphql("pull_requests_query", owner, name, filter, { escape = false })
  print "Fetching pull requests (this may take a while) ..."
  gh.run {
    args = { "api", "graphql", "--paginate", "--jq", ".", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      print " "
      if stderr and not utils.is_blank(stderr) then
        utils.notify(stderr, 2)
      elseif output then
        local resp = utils.aggregate_pages(output, "data.repository.pullRequests.nodes")
        local pull_requests = resp.data.repository.pullRequests.nodes
        if #pull_requests == 0 then
          utils.notify(string.format("There are no matching pull requests in %s.", opts.repo), 2)
          return
        end
        local max_number = -1
        for _, pull in ipairs(pull_requests) do
          if #tostring(pull.number) > max_number then
            max_number = #tostring(pull.number)
          end
        end
        opts.preview_title = opts.preview_title or ""
        opts.prompt_title = opts.prompt_title or ""
        opts.results_title = opts.results_title or ""
        pickers.new(opts, {
          finder = finders.new_table {
            results = pull_requests,
            entry_maker = entry_maker.gen_from_issue(max_number),
          },
          sorter = conf.generic_sorter(opts),
          previewer = previewers.issue.new(opts),
          attach_mappings = function(_, map)
            action_set.select:replace(function(prompt_bufnr, type)
              open(type)(prompt_bufnr)
            end)
            map("i", "<c-o>", checkout_pull_request())
            map("i", "<c-b>", open_in_browser())
            map("i", "<c-y>", copy_url())
            return true
          end,
        }):find()
      end
    end,
  }
end

--
-- COMMITS
--
function M.commits()
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer or not buffer:isPullRequest() then
    return
  end
  -- TODO: graphql
  local url = string.format("repos/%s/pulls/%d/commits", buffer.repo, buffer.number)
  gh.run {
    args = { "api", url },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.notify(stderr, 2)
      elseif output then
        local results = vim.fn.json_decode(output)
        pickers.new({}, {
          prompt_title = false,
          results_title = false,
          preview_title = false,
          finder = finders.new_table {
            results = results,
            entry_maker = entry_maker.gen_from_git_commits(),
          },
          sorter = conf.generic_sorter {},
          previewer = previewers.commit.new { repo = buffer.repo },
          attach_mappings = function()
            action_set.select:replace(function(prompt_bufnr, type)
              open_preview_buffer(type)(prompt_bufnr)
            end)
            return true
          end,
        }):find()
      end
    end,
  }
end

--
-- FILES
--
function M.changed_files()
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer or not buffer:isPullRequest() then
    return
  end
  local url = string.format("repos/%s/pulls/%d/files", buffer.repo, buffer.number)
  gh.run {
    args = { "api", url },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.notify(stderr, 2)
      elseif output then
        local results = vim.fn.json_decode(output)
        pickers.new({}, {
          prompt_title = false,
          results_title = false,
          preview_title = false,
          finder = finders.new_table {
            results = results,
            entry_maker = entry_maker.gen_from_git_changed_files(),
          },
          sorter = conf.generic_sorter {},
          previewer = previewers.changed_files.new { repo = buffer.repo, number = buffer.number },
          attach_mappings = function()
            action_set.select:replace(function(prompt_bufnr, type)
              open_preview_buffer(type)(prompt_bufnr)
            end)
            return true
          end,
        }):find()
      end
    end,
  }
end

---
-- SEARCH
---
function M.search(opts)
  opts = opts or {}

  local requester = function()
    return function(prompt)
      if not opts.prompt and utils.is_blank(prompt) then
        return {}
      end
      if opts.prompt then
        prompt = string.format("%s %s", opts.prompt, prompt)
      end
      if opts.repo then
        prompt = string.format("repo:%s %s", opts.repo, prompt)
      end
      local query = graphql("search_query", prompt)
      local output = gh.run {
        args = { "api", "graphql", "-f", string.format("query=%s", query) },
        mode = "sync",
      }
      if output then
        local resp = vim.fn.json_decode(output)
        local results = {}
        for _, issue in ipairs(resp.data.search.nodes) do
          table.insert(results, issue)
        end
        return results
      else
        return {}
      end
    end
  end
  local finder = finders.new_dynamic {
    fn = requester(),
    entry_maker = entry_maker.gen_from_issue(6),
  }
  if opts.static then
    local results = requester() ""
    finder = finders.new_table {
      results = results,
      entry_maker = entry_maker.gen_from_issue(6, true),
    }
  end
  opts.preview_title = opts.preview_title or ""
  opts.prompt_title = opts.prompt_title or ""
  opts.results_title = opts.results_title or ""
  pickers.new(opts, {
    finder = finder,
    sorter = conf.generic_sorter(opts),
    previewer = previewers.issue.new(opts),
    attach_mappings = function(_, map)
      action_set.select:replace(function(prompt_bufnr, type)
        open(type)(prompt_bufnr)
      end)
      map("i", "<c-b>", open_in_browser())
      map("i", "<c-y>", copy_url())
      return true
    end,
  }):find()
end

---
-- REVIEW COMMENTS
---
function M.pending_threads(threads)
  local max_linenr_length = -1
  for _, thread in ipairs(threads) do
    max_linenr_length = math.max(max_linenr_length, #tostring(thread.startLine))
    max_linenr_length = math.max(max_linenr_length, #tostring(thread.line))
  end
  pickers.new({}, {
    prompt_title = false,
    results_title = false,
    preview_title = false,
    finder = finders.new_table {
      results = threads,
      entry_maker = entry_maker.gen_from_review_thread(max_linenr_length),
    },
    sorter = conf.generic_sorter {},
    previewer = previewers.review_thread.new {},
    attach_mappings = function()
      actions.select_default:replace(function(prompt_bufnr)
        local thread = action_state.get_selected_entry(prompt_bufnr).thread
        actions.close(prompt_bufnr)
        reviews.jump_to_pending_review_thread(thread)
      end)
      return true
    end,
  }):find()
end

---
-- PROJECTS
---
function M.select_project_card(cb)
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  local cards = buffer.node.projectCards
  if not cards or #cards.nodes == 0 then
    utils.notify("Cant find any project cards", 2)
    return
  end

  if #cards.nodes == 1 then
    cb(cards.nodes[1].id)
  else
    local opts = vim.deepcopy(dropdown_opts)
    pickers.new(opts, {
      finder = finders.new_table {
        results = cards.nodes,
        entry_maker = entry_maker.gen_from_project_card(),
      },
      sorter = conf.generic_sorter(opts),
      attach_mappings = function(_, _)
        actions.select_default:replace(function(prompt_bufnr)
          local source_card = action_state.get_selected_entry(prompt_bufnr)
          actions.close(prompt_bufnr)
          cb(source_card.card.id)
        end)
        return true
      end,
    }):find()
  end
end

function M.select_target_project_column(cb)
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer then
    return
  end

  local query = graphql("projects_query", buffer.owner, buffer.name, vim.g.octo_viewer, buffer.owner)
  gh.run {
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
          utils.notify(string.format("There are no matching projects for %s.", buffer.repo), 2)
          return
        end

        local opts = vim.deepcopy(dropdown_opts)
        pickers.new(opts, {
          finder = finders.new_table {
            results = projects,
            entry_maker = entry_maker.gen_from_project(),
          },
          sorter = conf.generic_sorter(opts),
          attach_mappings = function()
            action_set.select:replace(function(prompt_bufnr)
              local selected_project = action_state.get_selected_entry(prompt_bufnr)
              actions._close(prompt_bufnr, true)
              local opts2 = vim.deepcopy(dropdown_opts)
              pickers.new(opts2, {
                finder = finders.new_table {
                  results = selected_project.project.columns.nodes,
                  entry_maker = entry_maker.gen_from_project_column(),
                },
                sorter = conf.generic_sorter(opts2),
                attach_mappings = function()
                  action_set.select:replace(function(prompt_bufnr2)
                    local selected_column = action_state.get_selected_entry(prompt_bufnr2)
                    actions.close(prompt_bufnr2)
                    cb(selected_column.column.id)
                  end)
                  return true
                end,
              }):find()
            end)
            return true
          end,
        }):find()
      end
    end,
  }
end

--
-- LABELS
--
function M.select_label(cb)
  local opts = vim.deepcopy(dropdown_opts)
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer then
    return
  end

  local query = graphql("labels_query", buffer.owner, buffer.name)
  gh.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.notify(stderr, 2)
      elseif output then
        local resp = vim.fn.json_decode(output)
        local labels = resp.data.repository.labels.nodes
        pickers.new(opts, {
          finder = finders.new_table {
            results = labels,
            entry_maker = entry_maker.gen_from_label(),
          },
          sorter = conf.generic_sorter(opts),
          attach_mappings = function(_, _)
            actions.select_default:replace(function(prompt_bufnr)
              local selected_label = action_state.get_selected_entry(prompt_bufnr)
              actions.close(prompt_bufnr)
              cb(selected_label.label.id)
            end)
            return true
          end,
        }):find()
      end
    end,
  }
end

function M.select_assigned_label(cb)
  local opts = vim.deepcopy(dropdown_opts)
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer then
    return
  end
  local query, key
  if buffer:isIssue() then
    query = graphql("issue_labels_query", buffer.owner, buffer.name, buffer.number)
    key = "issue"
  elseif buffer:isPullRequest() then
    query = graphql("pull_request_labels_query", buffer.owner, buffer.name, buffer.number)
    key = "pullRequest"
  end
  gh.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.notify(stderr, 2)
      elseif output then
        local resp = vim.fn.json_decode(output)
        local labels = resp.data.repository[key].labels.nodes
        pickers.new(opts, {
          finder = finders.new_table {
            results = labels,
            entry_maker = entry_maker.gen_from_label(),
          },
          sorter = conf.generic_sorter(opts),
          attach_mappings = function(_, _)
            actions.select_default:replace(function(prompt_bufnr)
              local selected_label = action_state.get_selected_entry(prompt_bufnr)
              actions.close(prompt_bufnr)
              cb(selected_label.label.id)
            end)
            return true
          end,
        }):find()
      end
    end,
  }
end

--
-- ASSIGNEES
--
function M.select_user(cb)
  local opts = vim.deepcopy(dropdown_opts)
  opts.layout_config = {
    width = 0.4,
    height = 15,
  }

  --local queue = {}
  local function get_user_requester()
    return function(prompt)
      -- skip empty queries
      if not prompt or prompt == "" or utils.is_blank(prompt) then
        return {}
      end
      local query = graphql("users_query", prompt)
      local output = gh.run {
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

        local results = {}
        -- process orgs with teams
        for _, user in pairs(users) do
          table.insert(results, user)
        end
        for _, org in pairs(orgs) do
          org.login = string.format("%s (%d)", org.login, #org.teams)
          table.insert(results, org)
        end
        return results
      else
        return {}
      end
    end
  end

  pickers.new(opts, {
    finder = finders.new_dynamic {
      entry_maker = entry_maker.gen_from_user(),
      fn = get_user_requester(),
    },
    sorter = sorters.get_fuzzy_file(opts),
    attach_mappings = function()
      actions.select_default:replace(function(prompt_bufnr)
        local selected_user = action_state.get_selected_entry(prompt_bufnr)
        actions._close(prompt_bufnr, true)
        if not selected_user.teams then
          -- user
          cb(selected_user.value)
        else
          -- organization, pick a team
          pickers.new(opts, {
            prompt_title = false,
            results_title = false,
            preview_title = false,
            finder = finders.new_table {
              results = selected_user.teams,
              entry_maker = entry_maker.gen_from_team(),
            },
            sorter = conf.generic_sorter(opts),
            attach_mappings = function()
              actions.select_default:replace(function(prompt_bufnr)
                local selected_team = action_state.get_selected_entry(prompt_bufnr)
                actions.close(prompt_bufnr)
                cb(selected_team.team.id)
              end)
              return true
            end,
          }):find()
        end
      end)
      return true
    end,
  }):find()
end

--
-- ASSIGNEES
--
function M.select_assignee(cb)
  local opts = vim.deepcopy(dropdown_opts)
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer then
    return
  end
  local query, key
  if buffer:isIssue() then
    query = graphql("issue_assignees_query", buffer.owner, buffer.name, buffer.number)
    key = "issue"
  elseif buffer:isPullRequest() then
    query = graphql("pull_request_assignees_query", buffer.owner, buffer.name, buffer.number)
    key = "pullRequest"
  end
  gh.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.notify(stderr, 2)
      elseif output then
        local resp = vim.fn.json_decode(output)
        local assignees = resp.data.repository[key].assignees.nodes
        pickers.new(opts, {
          finder = finders.new_table {
            results = assignees,
            entry_maker = entry_maker.gen_from_user(),
          },
          sorter = conf.generic_sorter(opts),
          attach_mappings = function(_, _)
            actions.select_default:replace(function(prompt_bufnr)
              local selected_assignee = action_state.get_selected_entry(prompt_bufnr)
              actions.close(prompt_bufnr)
              cb(selected_assignee.user.id)
            end)
            return true
          end,
        }):find()
      end
    end,
  }
end

--
-- REPOS
--
function M.repos(opts)
  opts = opts or {}
  if not opts.login then
    if vim.g.octo_viewer then
      opts.login = vim.g.octo_viewer
    else
      opts.login = require("octo.gh").get_user_name()
    end
  end

  local query = graphql("repos_query", opts.login)
  print "Fetching repositories (this may take a while) ..."
  gh.run {
    args = { "api", "graphql", "--paginate", "--jq", ".", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      print " "
      if stderr and not utils.is_blank(stderr) then
        utils.notify(stderr, 2)
      elseif output then
        local resp = utils.aggregate_pages(output, "data.repositoryOwner.repositories.nodes")
        local repos = resp.data.repositoryOwner.repositories.nodes
        if #repos == 0 then
          utils.notify(string.format("There are no matching repositories for %s.", opts.login), 2)
          return
        end
        local max_nameWithOwner = -1
        local max_forkCount = -1
        local max_stargazerCount = -1
        for _, repo in ipairs(repos) do
          max_nameWithOwner = math.max(max_nameWithOwner, #repo.nameWithOwner)
          max_forkCount = math.max(max_forkCount, #tostring(repo.forkCount))
          max_stargazerCount = math.max(max_stargazerCount, #tostring(repo.stargazerCount))
        end
        opts.preview_title = opts.preview_title or ""
        opts.prompt_title = opts.prompt_title or ""
        opts.results_title = opts.results_title or ""
        pickers.new(opts, {
          finder = finders.new_table {
            results = repos,
            entry_maker = entry_maker.gen_from_repo(max_nameWithOwner, max_forkCount, max_stargazerCount),
          },
          sorter = conf.generic_sorter(opts),
          attach_mappings = function(_, map)
            action_set.select:replace(function(prompt_bufnr, type)
              open(type)(prompt_bufnr)
            end)
            map("i", "<c-b>", open_in_browser())
            map("i", "<c-y>", copy_url())
            return true
          end,
        }):find()
      end
    end,
  }
end

--
-- OCTO
--
function M.actions(flattened_actions)
  local opts = {
    preview_title = "",
    prompt_title = "",
    results_title = "",
  }

  pickers.new(opts, {
    finder = finders.new_table {
      results = flattened_actions,
      entry_maker = entry_maker.gen_from_octo_actions(),
    },
    sorter = conf.generic_sorter(opts),
    attach_mappings = function()
      actions.select_default:replace(function(prompt_bufnr)
        local selected_command = action_state.get_selected_entry(prompt_bufnr)
        actions.close(prompt_bufnr)
        selected_command.action.fun()
      end)
      return true
    end,
  }):find()
end

M.picker = {
  issues = M.issues,
  prs = M.pull_requests,
  gists = M.gists,
  commits = M.commits,
  changed_files = M.changed_files,
  pending_threads = M.pending_threads,
  project_cards = M.select_project_card,
  project_columns = M.select_target_project_column,
  labels = M.select_label,
  assigned_labels = M.select_assigned_label,
  users = M.select_user,
  assignees = M.select_assignee,
  repos = M.repos,
  search = M.search,
  actions = M.actions,
}

return M
