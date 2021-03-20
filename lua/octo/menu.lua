local actions = require "telescope.actions"
local action_state = require "telescope.actions.state"
local action_set = require "telescope.actions.set"
local finders = require "telescope.finders"
local pickers = require "telescope.pickers"
local utils = require "telescope.utils"
local conf = require "telescope.config".values
local sorters = require "telescope.sorters"
local make_entry = require "telescope.make_entry"
local previewers = require "octo.previewers"
local reviews = require "octo.reviews"
local gh = require "octo.gh"
local util = require "octo.util"
local navigation = require "octo.navigation"
local graphql = require "octo.graphql"
local entry_maker = require "octo.entry_maker"
local format = string.format
local vim = vim
local api = vim.api
local json = {
  parse = vim.fn.json_decode,
  stringify = vim.fn.json_encode
}

local M = {}

local dropdown_opts = require('telescope.themes').get_dropdown({
  results_height = 15;
  width = 0.4;
  prompt_title = '';
  previewer = false;
  borderchars = {
    prompt = {'▀', '▐', '▄', '▌', '▛', '▜', '▟', '▙' };
    results = {' ', '▐', '▄', '▌', '▌', '▐', '▟', '▙' };
    preview = {'▀', '▐', '▄', '▌', '▛', '▜', '▟', '▙' };
  };
})

local function get_filter(opts, kind)
  local filter = ""
  local allowed_values = {}
  if kind == "issue" then
    allowed_values = {"since", "createdBy", "assignee", "mentioned", "labels", "milestone", "states"}
  elseif kind == "pull_request" then
    allowed_values = {"baseRefName", "headRefName", "labels", "states"}
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
      val = json.stringify(val)
      val = string.gsub(val, '"OPEN"', "OPEN")
      val = string.gsub(val, '"CLOSED"', "CLOSED")
      val = string.gsub(val, '"MERGED"', "MERGED")
      filter = filter .. value .. ":" .. val .. ","
    end
  end

  return filter
end

local function open(repo, what, command)
  return function(prompt_bufnr)
    local selection = action_state.get_selected_entry(prompt_bufnr)
    actions.close(prompt_bufnr)
    if command == 'default' then
      vim.cmd [[:buffer %]]
    elseif command == 'horizontal' then
      vim.cmd [[:sbuffer %]]
    elseif command == 'vertical' then
      vim.cmd [[:vert sbuffer %]]
    elseif command == 'tab' then
      vim.cmd [[:tab sb %]]
    end
    vim.cmd(string.format([[ lua require'octo.util'.get_%s('%s', '%s') ]], what, repo, selection.value))
  end
end

local function open_preview_buffer(command)
  return function(prompt_bufnr)
    actions.close(prompt_bufnr)
    local preview_bufnr = require "telescope.state".get_global_key("last_preview_bufnr")
    if command == 'edit' then
      vim.cmd(string.format(":buffer %d", preview_bufnr))
    elseif command == 'split' then
      vim.cmd(string.format(":sbuffer %d", preview_bufnr))
    elseif command == 'vsplit' then
      vim.cmd(string.format(":vert sbuffer %d", preview_bufnr))
    elseif command == 'tabedit' then
      vim.cmd(string.format(":tab sb %d", preview_bufnr))
    end
    vim.cmd [[stopinsert]]
  end
end

local function open_in_browser(type, repo)
  return function(prompt_bufnr)
    local selection = action_state.get_selected_entry(prompt_bufnr)
    local number = selection.value
    actions.close(prompt_bufnr)
    navigation.open_in_browser(type, repo, number)
  end
end

--
-- ISSUES
--
function M.issues(opts)
  opts = opts or {}
  local filter = get_filter(opts, "issue")

  if not opts.repo or opts.repo == vim.NIL then
    opts.repo = util.get_remote_name()
  end
  if not opts.repo then
    api.nvim_err_writeln("Cannot find repo")
    return
  end

  local owner, name = util.split_repo(opts.repo)
  local query = graphql("issues_query", owner, name, filter, {escape = false})
  print("Fetching issues (this may take a while) ...")
  gh.run(
    {
      args = {"api", "graphql", "--paginate", "-f", format("query=%s", query)},
      cb = function(output, stderr)
        if stderr and not util.is_blank(stderr) then
          api.nvim_err_writeln(stderr)
        elseif output then
          print(" ")
          local resp = util.aggregate_pages(output, "data.repository.issues.nodes")
          local issues = resp.data.repository.issues.nodes
          if #issues == 0 then
            api.nvim_err_writeln(format("There are no matching issues in %s.", opts.repo))
            return
          end
          local max_number = -1
          for _, issue in ipairs(issues) do
            if #tostring(issue.number) > max_number then
              max_number = #tostring(issue.number)
            end
          end

          pickers.new(
            opts,
            {
              prompt_prefix = "Issues >",
              finder = finders.new_table {
                results = issues,
                entry_maker = entry_maker.gen_from_issue(max_number)
              },
              sorter = conf.generic_sorter(opts),
              previewer = previewers.issue.new(opts),
              attach_mappings = function(_, map)
                action_set.select:replace(function(prompt_bufnr, type)
                  open(opts.repo, "issue", type)(prompt_bufnr)
                end)
                map("i", "<c-b>", open_in_browser("issue", opts.repo))
                return true
              end
            }
          ):find()
        end
      end
    }
  )
end

--
-- GISTS
--
local function open_gist(prompt_bufnr)
  local selection = action_state.get_selected_entry(prompt_bufnr)
  actions.close(prompt_bufnr)
  local tmp_table = vim.split(selection.value, "\t")
  if vim.tbl_isempty(tmp_table) then
    return
  end
  local gist_id = tmp_table[1]
  local gist = utils.get_os_command_output({"gh", "gist", "view",  gist_id, "-r"})
  if gist and vim.api.nvim_buf_get_option(vim.api.nvim_get_current_buf(), "modifiable") then
    api.nvim_put(gist, "b", true, true)
  end
end

function M.gists(opts)
  opts = opts or {}
  opts.limit = opts.limit or 100
  local cmd = {"gh", "gist", "list", "--limit", opts.limit}
  if opts.public then
    table.insert(cmd, "--public")
  end
  if opts.secret then
    table.insert(cmd, "--secret")
  end
  local output = utils.get_os_command_output(cmd)
  if not output or #output == 0 then
    api.nvim_err_writeln("No gists found")
    return
  end

  -- TODO: make a decent displayer
 
  pickers.new(
    opts,
    {
      prompt_prefix = "Gists >",
      finder = finders.new_table {
        results = output,
        entry_maker = make_entry.gen_from_string(opts)
      },
      previewer = previewers.gist.new(opts),
      sorter = conf.generic_sorter(opts),
      attach_mappings = function(_, map)
        map("i", "<CR>", open_gist)
        map("i", "<c-b>", open_in_browser("gist"))
        return true
      end
    }
  ):find()
end

--
-- PULL REQUESTS
--

local function checkout_pull_request(repo)
  return function(prompt_bufnr)
    local selection = action_state.get_selected_entry(prompt_bufnr)
    actions.close(prompt_bufnr)
    local tmp_table = vim.split(selection.value, "\t")
    if vim.tbl_isempty(tmp_table) then
      return
    end
    local number = tmp_table[1]
    local args = {"pr", "checkout", number, "-R", repo}
    if repo == "" then
      args = {"pr", "checkout", number}
    end
    gh.run(
      {
        args = args,
        cb = function(output)
          print(output)
          print(format("Checked out PR %d", number))
        end
      }
    )
  end
end

function M.pull_requests(opts)
  opts = opts or {}
  if not opts.states then
    opts.states = "OPEN"
  end

  local filter = get_filter(opts, "pull_request")

  if not opts.repo or opts.repo == vim.NIL then
    opts.repo = util.get_remote_name()
  end
  if not opts.repo then
    api.nvim_err_writeln("Cannot find repo")
    return
  end

  local owner, name = util.split_repo(opts.repo)
  local query = graphql("pull_requests_query", owner, name, filter, {escape = false})
  print("Fetching issues (this may take a while) ...")
  gh.run(
    {
      args = {"api", "graphql", "--paginate", "-f", format("query=%s", query)},
      cb = function(output, stderr)
        if stderr and not util.is_blank(stderr) then
          api.nvim_err_writeln(stderr)
        elseif output then
          print(" ")
          local resp = util.aggregate_pages(output, "data.repository.pullRequests.nodes")
          local pull_requests = resp.data.repository.pullRequests.nodes
          if #pull_requests == 0 then
            api.nvim_err_writeln(format("There are no matching pull requests in %s.", opts.repo))
            return
          end
          local max_number = -1
          for _, pull in ipairs(pull_requests) do
            if #tostring(pull.number) > max_number then
              max_number = #tostring(pull.number)
            end
          end

          pickers.new(
            opts,
            {
              prompt_prefix = "Pull Requests >",
              finder = finders.new_table {
                results = pull_requests,
                entry_maker = entry_maker.gen_from_pull_request(max_number)
              },
              sorter = conf.generic_sorter(opts),
              previewer = previewers.pull_request.new(opts),
              attach_mappings = function(_, map)
                action_set.select:replace(function(prompt_bufnr, type)
                  open(opts.repo, "pull_request", type)(prompt_bufnr)
                end)
                map("i", "<c-o>", checkout_pull_request(opts.repo))
                map("i", "<c-b>", open_in_browser("pr", opts.repo))
                return true
              end
            }
          ):find()
        end
      end
    }
  )
end

--
-- COMMITS
--
function M.commits()
  local repo, number, _ = util.get_repo_number_pr()
  if not repo then
    return
  end
  -- TODO: graphql
  local url = format("repos/%s/pulls/%d/commits", repo, number)
  gh.run(
    {
      args = {"api", url},
      cb = function(output, stderr)
        if stderr and not util.is_blank(stderr) then
          api.nvim_err_writeln(stderr)
        elseif output then
          local results = json.parse(output)
          pickers.new(
            {},
            {
              prompt_prefix = "PR Commits >",
              finder = finders.new_table {
                results = results,
                entry_maker = entry_maker.gen_from_git_commits()
              },
              sorter = conf.generic_sorter({}),
              previewer = previewers.commit.new({repo = repo}),
              attach_mappings = function()
                action_set.select:replace(function(prompt_bufnr, type)
                  open_preview_buffer(type)(prompt_bufnr)
                end)
                return true
              end
            }
          ):find()
        end
      end
    }
  )
end

--
-- FILES
--
function M.changed_files()
  local repo, number, _ = util.get_repo_number_pr()
  if not repo then
    return
  end
  local url = format("repos/%s/pulls/%d/files", repo, number)
  gh.run(
    {
      args = {"api", url},
      cb = function(output, stderr)
        if stderr and not util.is_blank(stderr) then
          api.nvim_err_writeln(stderr)
        elseif output then
          local results = json.parse(output)
          pickers.new(
            {},
            {
              prompt_prefix = "PR Files Changed >",
              finder = finders.new_table {
                results = results,
                entry_maker = entry_maker.gen_from_git_changed_files()
              },
              sorter = conf.generic_sorter({}),
              previewer = previewers.changed_files.new({repo = repo, number = number}),
              attach_mappings = function()
                action_set.select:replace(function(prompt_bufnr, type)
                  open_preview_buffer(type)(prompt_bufnr)
                end)
                return true
              end
            }
          ):find()
        end
      end
    }
  )
end

---
-- SEARCH
---

function M.issue_search(opts)
  opts = opts or {}

  if not opts.repo or opts.repo == vim.NIL then
    opts.repo = util.get_remote_name()
  end
  if not opts.repo then
    api.nvim_err_writeln("Cannot find repo")
    return
  end

  local queue = {}
  pickers.new(
    opts,
    {
      prompt_prefix = "Issue Search >",
      finder = function(prompt, process_result, process_complete)
        if not prompt or prompt == "" then
          return nil
        end
        prompt = prompt

        -- skip requests for empty prompts
        if util.is_blank(prompt) then
          process_complete()
          return
        end

        -- store prompt in request queue
        table.insert(queue, prompt)

        -- defer api call so that finder finishes and takes more keystrokes
        vim.defer_fn(function()

          -- do not process response, if this is not the last request we sent
          if prompt ~= queue[#queue] then
            process_complete()
            return
          end

          local query = graphql("search_issues_query", opts.repo, prompt)
          gh.run(
            {
              args = {"api", "graphql", "-f", format("query=%s", query)},
              cb = function(output, stderr)

                -- do not process response, if this is not the last request we sent
                if prompt ~= queue[#queue] then
                  process_complete()
                  return
                end

                if stderr and not util.is_blank(stderr) then
                  api.nvim_err_writeln(stderr)
                elseif output then
                  local resp = json.parse(output)
                  for _, issue in ipairs(resp.data.search.nodes) do
                    process_result(entry_maker.gen_from_issue(6)(issue))
                  end
                  process_complete()
                end
              end
            }
          )
        end, 500)
      end,
      sorter = conf.generic_sorter(opts),
      previewer = previewers.issue.new(opts),
      attach_mappings = function(_, map)
        action_set.select:replace(function(prompt_bufnr, type)
          open(opts.repo, "issue", type)(prompt_bufnr)
        end)
        map("i", "<c-b>", open_in_browser("issue", opts.repo))
        return true
      end
    }
  ):find()
end

function M.pull_request_search(opts)
  opts = opts or {}

  if not opts.repo or opts.repo == vim.NIL then
    opts.repo = util.get_remote_name()
  end
  if not opts.repo then
    api.nvim_err_writeln("Cannot find repo")
    return
  end

  local queue = {}
  pickers.new(
    opts,
    {
      prompt_prefix = "PR Search >",
      finder = function(prompt, process_result, process_complete)
        if not prompt or prompt == "" then
          return nil
        end
        prompt = prompt

        -- skip requests for empty prompts
        if util.is_blank(prompt) then
          process_complete()
          return
        end

        -- store prompt in request queue
        table.insert(queue, prompt)

        -- defer api call so that finder finishes and takes more keystrokes
        vim.defer_fn(function()

          -- do not process response, if this is not the last request we sent
          if prompt ~= queue[#queue] then
            process_complete()
            return
          end

          local query = graphql("search_pull_requests_query", opts.repo, prompt)
          gh.run(
            {
              args = {"api", "graphql", "-f", format("query=%s", query)},
              cb = function(output, stderr)

                -- do not process response, if this is not the last request we sent
                if prompt ~= queue[#queue] then
                  process_complete()
                  return
                end

                if stderr and not util.is_blank(stderr) then
                  api.nvim_err_writeln(stderr)
                elseif output then
                  local resp = json.parse(output)
                  for _, pull_request in ipairs(resp.data.search.nodes) do
                    process_result(entry_maker.gen_from_pull_request(6)(pull_request))
                  end
                  process_complete()
                end
              end
            }
          )
        end, 500)
      end,
      sorter = conf.generic_sorter(opts),
      previewer = previewers.pull_request.new(opts),
      attach_mappings = function(_, map)
        action_set.select:replace(function(prompt_bufnr, type)
          open(opts.repo, "pull_request", type)(prompt_bufnr)
        end)
        map("i", "<c-b>", open_in_browser("pr", opts.repo))
        return true
      end
    }
  ):find()
end

---
-- REVIEW COMMENTS
---
function M.pending_comments(comments)
  local max_linenr_length = -1
  for _, comment in ipairs(comments) do
    max_linenr_length = math.max(max_linenr_length, #tostring(comment.startLine))
    max_linenr_length = math.max(max_linenr_length, #tostring(comment.line))
  end
  pickers.new(
    {},
    {
      prompt_prefix = "Review Comments >",
      finder = finders.new_table {
        results = comments,
        entry_maker = entry_maker.gen_from_review_comment(max_linenr_length)
      },
      sorter = conf.generic_sorter({}),
      previewer = previewers.review_comment.new({}),
      attach_mappings = function(_, map)

        -- update comment mapping
        map("i", "<c-e>", function(prompt_bufnr)
          local comment = action_state.get_selected_entry(prompt_bufnr).comment
          actions.close(prompt_bufnr)
          reviews.update_pending_review_comment(comment)
        end)

        -- delete comment mapping
        map("i", "<c-d>", function(prompt_bufnr)
          local comment = action_state.get_selected_entry(prompt_bufnr).comment
          actions.close(prompt_bufnr)
          reviews.delete_pending_review_comment(comment)
        end)

        -- jump to comment
        actions.select_default:replace(function(prompt_bufnr)
          local comment = action_state.get_selected_entry(prompt_bufnr).comment
          actions.close(prompt_bufnr)
          reviews.jump_to_pending_review_comment(comment)
        end)
        return true
      end
    }
  ):find()
end

---
-- PROJECTS
---
function M.select_project_card(cb)
  local opts = vim.deepcopy(dropdown_opts)
  local ok, cards = pcall(api.nvim_buf_get_var, 0, "cards")
  if not ok or not cards or #cards.nodes == 0 then
    api.nvim_err_writeln("Cant find any project cards")
    return
  end

  if #cards.nodes == 1 then
    cb(cards.nodes[1].id)
  else
    pickers.new(
      opts,
      {
        prompt_prefix = "Choose card >",
        finder = finders.new_table {
          results = cards.nodes,
          entry_maker = entry_maker.gen_from_project_card()
        },
        sorter = conf.generic_sorter(opts),
        attach_mappings = function(_, _)
          actions.select_default:replace(function(prompt_bufnr)
            local source_card = action_state.get_selected_entry(prompt_bufnr)
            actions.close(prompt_bufnr)
            cb(source_card.card.id)
          end)
          return true
        end
      }
    ):find()
  end
end

function M.select_target_project_column(cb)
  local opts = vim.deepcopy(dropdown_opts)

  local repo = util.get_repo_number()
  if not repo then
    return
  end

  local owner, name = util.split_repo(repo)
  local query = graphql("projects_query", owner, name, vim.g.octo_viewer, owner)
  gh.run(
    {
      args = {"api", "graphql", "--paginate", "-f", format("query=%s", query)},
      cb = function(output)
        if output then
          local resp = json.parse(output)
          local projects = {}
          local user_projects = resp.data.user and resp.data.user.projects.nodes or {}
          local repo_projects = resp.data.repository and resp.data.repository.projects.nodes or {}
          local org_projects = not resp.errors and resp.data.organization.projects.nodes or {}
          vim.list_extend(projects, repo_projects)
          vim.list_extend(projects, user_projects)
          vim.list_extend(projects, org_projects)
          if #projects == 0 then
            api.nvim_err_writeln(format("There are no matching projects for %s.", repo))
            return
          end

          pickers.new(
            opts,
            {
              prompt_prefix = "Choose target project >",
              finder = finders.new_table {
                results = projects,
                entry_maker = entry_maker.gen_from_project()
              },
              sorter = conf.generic_sorter(opts),
              attach_mappings = function(_, _)
                actions.select_default:replace(function(prompt_bufnr)
                  local selected_project = action_state.get_selected_entry(prompt_bufnr)
                  actions.close(prompt_bufnr)
                  local opts2 = vim.deepcopy(dropdown_opts)
                  pickers.new(
                    opts2,
                    {
                      prompt_prefix = "Choose target column >",
                      finder = finders.new_table {
                        results = selected_project.project.columns.nodes,
                        entry_maker = entry_maker.gen_from_project_column()
                      },
                      sorter = conf.generic_sorter(opts2),
                      attach_mappings = function()
                        actions.select_default:replace(function(prompt_bufnr)
                          actions.close(prompt_bufnr)
                          local selected_column = action_state.get_selected_entry(prompt_bufnr)
                          cb(selected_column.column.id)
                        end)
                        return true
                      end
                    }
                  ):find()
                end)
                return true
              end
            }
          ):find()
        end
      end
    }
  )
end

--
-- LABELS
--
function M.select_label(cb)
  local opts = vim.deepcopy(dropdown_opts)
  local repo = util.get_repo_number()
  if not repo then
    return
  end

  local owner, name = util.split_repo(repo)
  local query = graphql("labels_query", owner, name)
  gh.run(
    {
      args = {"api", "graphql", "-f", format("query=%s", query)},
      cb = function(output, stderr)
        if stderr and not util.is_blank(stderr) then
          api.nvim_err_writeln(stderr)
        elseif output then
          local resp = json.parse(output)
          local labels = resp.data.repository.labels.nodes
          pickers.new(
            opts,
            {
              prompt_prefix = "Choose label >",
              finder = finders.new_table {
                results = labels,
                entry_maker = entry_maker.gen_from_label()
              },
              sorter = conf.generic_sorter(opts),
              attach_mappings = function(_, _)
                actions.select_default:replace(function(prompt_bufnr)
                  local selected_label = action_state.get_selected_entry(prompt_bufnr)
                  actions.close(prompt_bufnr)
                  cb(selected_label.label.id)
                end)
                return true
              end
            }
          ):find()
        end
      end
    }
  )
end

function M.select_assigned_label(cb)
  local opts = vim.deepcopy(dropdown_opts)
  local repo, number = util.get_repo_number()
  if not repo then
    return
  end
  local bufnr = api.nvim_get_current_buf()
  local bufname = vim.fn.bufname(bufnr)
  local _, type = string.match(bufname, "octo://(.+)/(.+)/(%d+)")
  local owner, name = util.split_repo(repo)
  local query, key
  if type == "issue" then
    query = graphql("issue_labels_query", owner, name, number)
    key = "issue"
  elseif type == "pull" then
    query = graphql("pull_request_labels_query", owner, name, number)
    key = "pullRequest"
  end
  gh.run(
    {
      args = {"api", "graphql", "-f", format("query=%s", query)},
      cb = function(output, stderr)
        if stderr and not util.is_blank(stderr) then
          api.nvim_err_writeln(stderr)
        elseif output then
          local resp = json.parse(output)
          local labels = resp.data.repository[key].labels.nodes
          pickers.new(
            opts,
            {
              prompt_prefix = "Choose label >",
              finder = finders.new_table {
                results = labels,
                entry_maker = entry_maker.gen_from_label()
              },
              sorter = conf.generic_sorter(opts),
              attach_mappings = function(_, _)
                actions.select_default:replace(function(prompt_bufnr)
                  local selected_label = action_state.get_selected_entry(prompt_bufnr)
                  actions.close(prompt_bufnr)
                  cb(selected_label.label.id)
                end)
                return true
              end
            }
          ):find()
        end
      end
    }
  )
end

--
-- ASSIGNEES
--
function M.select_user(cb)
  local opts = vim.deepcopy(dropdown_opts)
  opts.results_height = 35;

  local queue = {}
  pickers.new(
    opts,
    {
      prompt_prefix = "User Search >",
      finder = function(prompt, process_result, process_complete)
        if not prompt or prompt == "" then
          return nil
        end
        prompt = "repos:>10 " .. prompt

        -- skip requests for empty prompts
        if util.is_blank(prompt) then
          process_complete()
          return
        end

        -- store prompt in request queue
        table.insert(queue, prompt)

        -- defer api call so that finder finishes and takes more keystrokes
        vim.defer_fn(function()

          -- do not process response, if this is not the last request we sent
          if prompt ~= queue[#queue] then
            process_complete()
            return
          end

          local query = graphql("user_query", prompt, prompt)
          gh.run(
            {
              args = {"api", "graphql", "--paginate", "-f", format("query=%s", query)},
              cb = function(output, stderr)
                if stderr and not util.is_blank(stderr) then
                  api.nvim_err_writeln(stderr)
                elseif output then
                  -- do not process response, if this is not the last request we sent
                  if prompt ~= queue[#queue] then
                    process_complete()
                    return
                  end
                  local users = {}
                  local orgs = {}
                  local responses = util.get_pages(output)
                  for _, resp in ipairs(responses) do
                    for _, user in ipairs(resp.data.search.nodes) do
                      if not user.teams then
                        -- regular user
                        if not vim.tbl_contains(vim.tbl_keys(users), user.login) then
                          users[user.login] = {
                            value = user.id,
                            text = user.login,
                            display = user.login,
                            ordinal = user.login,
                          }
                        end
                      elseif user.teams and user.teams.totalCount > 0 then
                        -- organization, collect all teams
                        if not vim.tbl_contains(vim.tbl_keys(orgs), user.login) then
                          orgs[user.login] = {
                            value = user.id,
                            text = user.login,
                            display = user.login,
                            ordinal = user.login,
                            teams = user.teams.nodes
                          }
                        else
                          vim.list_extend(orgs[user.login].teams, user.teams.nodes)
                        end
                      end
                    end
                  end

                  -- process users
                  for _, user in pairs(users) do
                    process_result(user)
                  end

                  -- process orgs with teams
                  for _, org in pairs(orgs) do
                    org.display = format("%s (%d)", org.text, #org.teams)
                    process_result(org)
                  end

                  -- call it done for the day
                  process_complete()
                  return
                end
              end
            }
          )
        end, 500)
      end,
      sorter = sorters.get_fuzzy_file(opts),
      attach_mappings = function()
        actions.select_default:replace(function(prompt_bufnr)
          local selected_user = action_state.get_selected_entry(prompt_bufnr)
          actions.close(prompt_bufnr)
          if not selected_user.teams then
            -- user
            cb(selected_user.value)
          else
            -- organization, pick a team
            pickers.new(
              opts,
              {
                prompt_prefix = "Choose team >",
                finder = finders.new_table {
                  results = selected_user.teams,
                  entry_maker = entry_maker.gen_from_team()
                },
                sorter = conf.generic_sorter(opts),
                attach_mappings = function(_, _)
                  actions.select_default:replace(function(prompt_bufnr)
                    local selected_team = action_state.get_selected_entry(prompt_bufnr)
                    actions.close(prompt_bufnr)
                    cb(selected_team.team.id)
                  end)
                  return true
                end
              }
            ):find()
          end
        end)
        return true
      end
    }
  ):find()
end

--
-- ASSIGNEES
--
function M.select_assignee(cb)
  local opts = vim.deepcopy(dropdown_opts)
  local repo, number = util.get_repo_number()
  if not repo then
    return
  end
  local bufnr = api.nvim_get_current_buf()
  local bufname = vim.fn.bufname(bufnr)
  local _, type = string.match(bufname, "octo://(.+)/(.+)/(%d+)")
  local owner, name = util.split_repo(repo)
  local query, key
  if type == "issue" then
    query = graphql("issue_assignees_query", owner, name, number)
    key = "issue"
  elseif type == "pull" then
    query = graphql("pull_request_assignees_query", owner, name, number)
    key = "pullRequest"
  end
  gh.run(
    {
      args = {"api", "graphql", "-f", format("query=%s", query)},
      cb = function(output, stderr)
        if stderr and not util.is_blank(stderr) then
          api.nvim_err_writeln(stderr)
        elseif output then
          local resp = json.parse(output)
          local assignees = resp.data.repository[key].assignees.nodes
          pickers.new(
            opts,
            {
              prompt_prefix = "Choose assignee >",
              finder = finders.new_table {
                results = assignees,
                entry_maker = entry_maker.gen_from_user()
              },
              sorter = conf.generic_sorter(opts),
              attach_mappings = function(_, _)
                actions.select_default:replace(function(prompt_bufnr)
                  local selected_assignee = action_state.get_selected_entry(prompt_bufnr)
                  actions.close(prompt_bufnr)
                  cb(selected_assignee.user.id)
                end)
                return true
              end
            }
          ):find()
        end
      end
    }
  )
end

return M
