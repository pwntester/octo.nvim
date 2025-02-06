local gh = require "octo.gh"
local graphql = require "octo.gh.graphql"
local navigation = require "octo.navigation"
local previewers = require "octo.pickers.telescope.previewers"
local entry_maker = require "octo.pickers.telescope.entry_maker"
local reviews = require "octo.reviews"
local utils = require "octo.utils"
local octo_config = require "octo.config"

local actions = require "telescope.actions"
local action_set = require "telescope.actions.set"
local action_state = require "telescope.actions.state"
local conf = require("telescope.config").values
local finders = require "telescope.finders"
local pickers = require "telescope.pickers"
local sorters = require "telescope.sorters"

local vim = vim

local M = {}

function M.not_implemented()
  utils.error "Not implemented yet"
end

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
      val = vim.json.encode(val)
      val = string.gsub(val, '"OPEN"', "OPEN")
      val = string.gsub(val, '"CLOSED"', "CLOSED")
      val = string.gsub(val, '"MERGED"', "MERGED")
      filter = filter .. value .. ":" .. val .. ","
    end
  end

  return filter
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
    if selection then
      utils.get(selection.kind, selection.value, selection.repo)
    end
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
    utils.info("Copied '" .. url .. "' to the system clipboard (+ register)")
  end
end

local function open_buffer(prompt_bufnr, type)
  open(type)(prompt_bufnr)
end

--
-- ISSUES
--

--- Create a replace function for the picker
--- @param cb function Callback function to call with the selected entry
--- @return function Replace function that takes a prompt_bufnr and calls the callback with the selected entry
local create_replace = function(cb)
  return function(prompt_bufnr, _)
    local selected = action_state.get_selected_entry()
    actions.close(prompt_bufnr)
    cb(selected)
  end
end

function M.issues(opts)
  opts = opts or {}
  if not opts.states then
    opts.states = "OPEN"
  end
  local filter = get_filter(opts, "issue")
  if utils.is_blank(opts.repo) then
    opts.repo = utils.get_remote_name()
  end
  if not opts.repo then
    utils.error "Cannot find repo"
    return
  end

  local replace = opts.cb and create_replace(opts.cb) or open_buffer

  local owner, name = utils.split_repo(opts.repo)
  local cfg = octo_config.values
  local order_by = cfg.issues.order_by
  local query = graphql("issues_query", owner, name, filter, order_by.field, order_by.direction, { escape = false })
  utils.info "Fetching issues (this may take a while) ..."
  gh.run {
    args = { "api", "graphql", "--paginate", "--jq", ".", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
      elseif output then
        local resp = utils.aggregate_pages(output, "data.repository.issues.nodes")
        local issues = resp.data.repository.issues.nodes
        if #issues == 0 then
          utils.error(string.format("There are no matching issues in %s.", opts.repo))
          return
        end
        local max_number = -1
        for _, issue in ipairs(issues) do
          if #tostring(issue.number) > max_number then
            max_number = #tostring(issue.number)
          end
        end
        opts.preview_title = opts.preview_title or ""
        opts.prompt_title = opts.prompt_title or ""
        opts.results_title = opts.results_title or ""

        pickers
          .new(opts, {
            finder = finders.new_table {
              results = issues,
              entry_maker = entry_maker.gen_from_issue(max_number),
            },
            sorter = conf.generic_sorter(opts),
            previewer = previewers.issue.new(opts),
            attach_mappings = function(_, map)
              action_set.select:replace(replace)
              map("i", cfg.picker_config.mappings.open_in_browser.lhs, open_in_browser())
              map("i", cfg.picker_config.mappings.copy_url.lhs, copy_url())
              return true
            end,
          })
          :find()
      end
    end,
  }
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
        utils.error(stderr)
      elseif output then
        local resp = utils.aggregate_pages(output, "data.viewer.gists.nodes")
        local gists = resp.data.viewer.gists.nodes
        opts.preview_title = opts.preview_title or ""
        opts.prompt_title = opts.prompt_title or ""
        opts.results_title = opts.results_title or ""
        pickers
          .new(opts, {
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
          })
          :find()
      end
    end,
  }
end

--
-- PULL REQUESTS
--

local function checkout_pull_request()
  return function(prompt_bufnr)
    local sel = action_state.get_selected_entry(prompt_bufnr)
    actions.close(prompt_bufnr)
    utils.checkout_pr(sel.obj.number)
  end
end

local function merge_pull_request()
  return function(prompt_bufnr)
    local sel = action_state.get_selected_entry(prompt_bufnr)
    actions.close(prompt_bufnr)
    utils.merge_pr(sel.obj.number)
  end
end

function M.pull_requests(opts)
  opts = opts or {}
  if not opts.states then
    opts.states = "OPEN"
  end
  local filter = get_filter(opts, "pull_request")
  if utils.is_blank(opts.repo) then
    opts.repo = utils.get_remote_name()
  end
  if not opts.repo then
    utils.error "Cannot find repo"
    return
  end

  local replace = opts.cb and create_replace(opts.cb) or open_buffer

  local owner, name = utils.split_repo(opts.repo)
  local cfg = octo_config.values
  local order_by = cfg.pull_requests.order_by
  local query =
    graphql("pull_requests_query", owner, name, filter, order_by.field, order_by.direction, { escape = false })
  utils.info "Fetching pull requests (this may take a while) ..."
  gh.run {
    args = { "api", "graphql", "--paginate", "--jq", ".", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
      elseif output then
        local resp = utils.aggregate_pages(output, "data.repository.pullRequests.nodes")
        local pull_requests = resp.data.repository.pullRequests.nodes
        if #pull_requests == 0 then
          utils.error(string.format("There are no matching pull requests in %s.", opts.repo))
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
        pickers
          .new(opts, {
            finder = finders.new_table {
              results = pull_requests,
              entry_maker = entry_maker.gen_from_issue(max_number),
            },
            sorter = conf.generic_sorter(opts),
            previewer = previewers.issue.new(opts),
            attach_mappings = function(_, map)
              action_set.select:replace(replace)
              map("i", cfg.picker_config.mappings.checkout_pr.lhs, checkout_pull_request())
              map("i", cfg.picker_config.mappings.open_in_browser.lhs, open_in_browser())
              map("i", cfg.picker_config.mappings.copy_url.lhs, copy_url())
              map("i", cfg.picker_config.mappings.merge_pr.lhs, merge_pull_request())
              return true
            end,
          })
          :find()
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
    args = { "api", "--paginate", url },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
      elseif output then
        local results = vim.json.decode(output)
        pickers
          .new({}, {
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
          })
          :find()
      end
    end,
  }
end

function M.review_commits(callback)
  local current_review = require("octo.reviews").get_current_review()
  if not current_review then
    utils.error "No review in progress"
    return
  end
  -- TODO: graphql
  local url =
    string.format("repos/%s/pulls/%d/commits", current_review.pull_request.repo, current_review.pull_request.number)
  gh.run {
    args = { "api", "--paginate", url },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
      elseif output then
        local results = vim.json.decode(output)

        -- add a fake entry to represent the entire pull request
        table.insert(results, {
          sha = current_review.pull_request.right.commit,
          commit = {
            message = "[[ENTIRE PULL REQUEST]]",
            author = {
              name = "",
              email = "",
              date = "",
            },
          },
          parents = {
            {
              sha = current_review.pull_request.left.commit,
            },
          },
        })

        pickers
          .new({}, {
            prompt_title = false,
            results_title = false,
            preview_title = false,
            finder = finders.new_table {
              results = results,
              entry_maker = entry_maker.gen_from_git_commits(),
            },
            sorter = conf.generic_sorter {},
            previewer = previewers.commit.new { repo = current_review.pull_request.repo },
            attach_mappings = function()
              action_set.select:replace(function(prompt_bufnr)
                local commit = action_state.get_selected_entry(prompt_bufnr)
                local right = commit.value
                local left = commit.parent
                actions.close(prompt_bufnr)
                callback(right, left)
              end)
              return true
            end,
          })
          :find()
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
    args = { "api", "--paginate", url },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
      elseif output then
        local results = vim.json.decode(output)
        pickers
          .new({}, {
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
          })
          :find()
      end
    end,
  }
end

---
-- SEARCH
---

local function get_search_query(prompt)
  local full_prompt = prompt[1]
  local parts = vim.split(full_prompt, " ")
  for _, part in ipairs(parts) do
    if string.match(part, "^repo:") then
      return {
        single_repo = true,
        prompt = part,
      }
    end
  end
  return {
    single_repo = false,
    prompt = full_prompt,
  }
end

local function get_search_size(prompt)
  local query = graphql("search_count_query", prompt)
  return gh.graphql {
    query = query,
    jq = ".data.search.issueCount",
    opts = {
      mode = "sync",
    },
  }
end

function M.search(opts)
  opts = opts or {}
  local cfg = octo_config.values
  if type(opts.prompt) == "string" then
    opts.prompt = { opts.prompt }
  end

  local search = get_search_query(opts.prompt)
  local width = 6
  if search.single_repo then
    local num_results = get_search_size(search.prompt)
    width = math.min(#num_results, width)
  end

  local replace = opts.cb and create_replace(opts.cb) or open_buffer

  local requester = function()
    return function(prompt)
      if utils.is_blank(opts.prompt) and utils.is_blank(prompt) then
        return {}
      end
      local results = {}
      for _, val in ipairs(opts.prompt) do
        local _prompt = prompt
        if val then
          _prompt = string.format("%s %s", val, _prompt)
        end
        local query = graphql("search_query", _prompt)
        local output = gh.run {
          args = { "api", "graphql", "-f", string.format("query=%s", query) },
          mode = "sync",
        }
        if output then
          local resp = vim.json.decode(output)
          for _, issue in ipairs(resp.data.search.nodes) do
            table.insert(results, issue)
          end
        end
      end
      return results
    end
  end
  local finder = finders.new_dynamic {
    fn = requester(),
    entry_maker = entry_maker.gen_from_issue(width),
  }
  if opts.static then
    local results = requester() ""
    finder = finders.new_table {
      results = results,
      entry_maker = entry_maker.gen_from_issue(width, true),
    }
  end
  opts.preview_title = opts.preview_title or ""
  opts.prompt_title = opts.prompt_title or ""
  opts.results_title = opts.results_title or ""
  pickers
    .new(opts, {
      finder = finder,
      sorter = conf.generic_sorter(opts),
      previewer = previewers.issue.new(opts),
      attach_mappings = function(_, map)
        action_set.select:replace(replace)
        map("i", cfg.picker_config.mappings.open_in_browser.lhs, open_in_browser())
        map("i", cfg.picker_config.mappings.copy_url.lhs, copy_url())
        if opts.search_prs then
          map("i", cfg.picker_config.mappings.checkout_pr.lhs, checkout_pull_request())
          map("i", cfg.picker_config.mappings.merge_pr.lhs, merge_pull_request())
        end
        return true
      end,
    })
    :find()
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
  pickers
    .new({}, {
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
    })
    :find()
end

---
-- PROJECTS
---
function M.select_project_card(cb)
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  local cards = buffer.node.projectCards
  if not cards or #cards.nodes == 0 then
    utils.error "Cant find any project cards"
    return
  end

  if #cards.nodes == 1 then
    cb(cards.nodes[1].id)
  else
    local opts = vim.deepcopy(dropdown_opts)
    pickers
      .new(opts, {
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
      })
      :find()
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
        local resp = vim.json.decode(output)
        local projects = {}
        local user_projects = resp.data.user and resp.data.user.projects.nodes or {}
        local repo_projects = resp.data.repository and resp.data.repository.projects.nodes or {}
        local org_projects = not resp.errors and resp.data.organization.projects.nodes or {}
        vim.list_extend(projects, repo_projects)
        vim.list_extend(projects, user_projects)
        vim.list_extend(projects, org_projects)
        if #projects == 0 then
          utils.error(string.format("There are no matching projects for %s.", buffer.repo))
          return
        end

        local opts = vim.deepcopy(dropdown_opts)
        pickers
          .new(opts, {
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
                pickers
                  .new(opts2, {
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
                  })
                  :find()
              end)
              return true
            end,
          })
          :find()
      end
    end,
  }
end

--
-- LABELS
--

local function select(opts)
  local prompt_bufnr = opts.bufnr
  local single_cb = opts.single_cb
  local multiple_cb = opts.multiple_cb
  local get_item = opts.get_item

  local picker = action_state.get_current_picker(prompt_bufnr)
  local selections = picker:get_multi_selection()
  local cb
  local items = {}
  if #selections == 0 then
    local selection = action_state.get_selected_entry(prompt_bufnr)
    table.insert(items, get_item(selection))
    cb = single_cb
  elseif multiple_cb == nil then
    utils.error "Multiple selections are not allowed"
    actions.close(prompt_bufnr)
    return
  else
    for _, selection in ipairs(selections) do
      table.insert(items, get_item(selection))
    end
    cb = multiple_cb
  end
  actions.close(prompt_bufnr)
  cb(items)
end

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
        utils.error(stderr)
      elseif output then
        local resp = vim.json.decode(output)
        local labels = resp.data.repository.labels.nodes
        pickers
          .new(opts, {
            finder = finders.new_table {
              results = labels,
              entry_maker = entry_maker.gen_from_label(),
            },
            sorter = conf.generic_sorter(opts),
            attach_mappings = function(_, _)
              actions.select_default:replace(function(prompt_bufnr)
                select {
                  bufnr = prompt_bufnr,
                  single_cb = cb,
                  multiple_cb = cb,
                  get_item = function(selection)
                    return selection.label
                  end,
                }
              end)
              return true
            end,
          })
          :find()
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
        utils.error(stderr)
      elseif output then
        local resp = vim.json.decode(output)
        local labels = resp.data.repository[key].labels.nodes
        pickers
          .new(opts, {
            finder = finders.new_table {
              results = labels,
              entry_maker = entry_maker.gen_from_label(),
            },
            sorter = conf.generic_sorter(opts),
            attach_mappings = function(_, _)
              actions.select_default:replace(function(prompt_bufnr)
                select {
                  bufnr = prompt_bufnr,
                  single_cb = cb,
                  multiple_cb = cb,
                  get_item = function(selection)
                    return selection.label
                  end,
                }
              end)
              return true
            end,
          })
          :find()
      end
    end,
  }
end

--
-- ASSIGNEES
--
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
      return {}
    end

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
              name = user.name,
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
  end
end

local function get_users(query_name, node_name)
  local repo = utils.get_remote_name()
  local owner, name = utils.split_repo(repo)
  local query = graphql(query_name, owner, name, { escape = true })
  local output = gh.run {
    args = { "api", "graphql", "--paginate", "-f", string.format("query=%s", query) },
    mode = "sync",
  }
  if not output then
    return {}
  end

  local responses = utils.get_pages(output)

  local users = {}

  for _, resp in ipairs(responses) do
    local nodes = resp.data.repository[node_name].nodes
    for _, user in ipairs(nodes) do
      table.insert(users, {
        id = user.id,
        login = user.login,
        name = user.name,
      })
    end
  end

  return users
end

local function get_assignable_users()
  return get_users("assignable_users_query", "assignableUsers")
end

local function get_mentionable_users()
  return get_users("mentionable_users_query", "mentionableUsers")
end

local function create_user_finder()
  local cfg = octo_config.values

  local finder
  local user_entry_maker = entry_maker.gen_from_user()
  if cfg.users == "search" then
    finder = finders.new_dynamic {
      entry_maker = user_entry_maker,
      fn = get_user_requester(),
    }
  elseif cfg.users == "assignable" then
    finder = finders.new_table {
      results = get_assignable_users(),
      entry_maker = user_entry_maker,
    }
  else
    finder = finders.new_table {
      results = get_mentionable_users(),
      entry_maker = user_entry_maker,
    }
  end

  return finder
end

function M.select_user(cb)
  local opts = vim.deepcopy(dropdown_opts)
  opts.layout_config = {
    width = 0.4,
    height = 15,
  }

  local finder = create_user_finder()

  pickers
    .new(opts, {
      finder = finder,
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
            pickers
              .new(opts, {
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
              })
              :find()
          end
        end)
        return true
      end,
    })
    :find()
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
        utils.error(stderr)
      elseif output then
        local resp = vim.json.decode(output)
        local assignees = resp.data.repository[key].assignees.nodes
        pickers
          .new(opts, {
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
          })
          :find()
      end
    end,
  }
end

--
-- REPOS
--
function M.repos(opts)
  opts = opts or {}
  local cfg = octo_config.values
  if not opts.login then
    if vim.g.octo_viewer then
      opts.login = vim.g.octo_viewer
    else
      local remote_hostname = require("octo.utils").get_remote_host()
      opts.login = require("octo.gh").get_user_name(remote_hostname)
    end
  end
  local query = graphql("repos_query", opts.login)
  utils.info "Fetching repositories (this may take a while) ..."
  gh.run {
    args = { "api", "graphql", "--paginate", "--jq", ".", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
      elseif output then
        local resp = utils.aggregate_pages(output, "data.repositoryOwner.repositories.nodes")
        local repos = resp.data.repositoryOwner.repositories.nodes
        if #repos == 0 then
          utils.error(string.format("There are no matching repositories for %s.", opts.login))
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
        pickers
          .new(opts, {
            finder = finders.new_table {
              results = repos,
              entry_maker = entry_maker.gen_from_repo(max_nameWithOwner, max_forkCount, max_stargazerCount),
            },
            sorter = conf.generic_sorter(opts),
            attach_mappings = function(_, map)
              action_set.select:replace(function(prompt_bufnr, type)
                open(type)(prompt_bufnr)
              end)
              map("i", cfg.picker_config.mappings.open_in_browser.lhs, open_in_browser())
              map("i", cfg.picker_config.mappings.copy_url.lhs, copy_url())
              return true
            end,
          })
          :find()
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

  local width = 11
  for _, action in ipairs(flattened_actions) do
    width = math.max(width, #action.object)
  end
  width = width + 1

  pickers
    .new(opts, {
      finder = finders.new_table {
        results = flattened_actions,
        entry_maker = entry_maker.gen_from_octo_actions(width),
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
    })
    :find()
end

--
-- NOTIFICATIONS
--
local function mark_notification_read()
  return function(prompt_bufnr)
    local current_picker = action_state.get_current_picker(prompt_bufnr)
    current_picker:delete_selection(function(selection)
      local url = string.format("/notifications/threads/%s", selection.thread_id)
      gh.run {
        args = { "api", "--method", "PATCH", url },
        headers = { "Accept: application/vnd.github.v3.diff" },
        cb = function(_, stderr)
          if stderr and not utils.is_blank(stderr) then
            utils.error(stderr)
            return
          end
        end,
      }
    end)
  end
end

function M.notifications(opts)
  opts = opts or {}
  local cfg = octo_config.values

  local endpoint = "/notifications"
  if opts.repo then
    local owner, name = utils.split_repo(opts.repo)
    endpoint = string.format("/repos/%s/%s/notifications", owner, name)
  end
  opts.prompt_title = opts.repo and string.format("%s Notifications", opts.repo) or "Github Notifications"

  opts.preview_title = ""
  opts.results_title = ""

  gh.run {
    args = { "api", "--paginate", endpoint },
    headers = { "Accept: application/vnd.github.v3.diff" },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
      elseif output then
        local resp = vim.json.decode(output)

        if #resp == 0 then
          utils.info "There are no notifications"
          return
        end

        pickers
          .new(opts, {
            finder = finders.new_table {
              results = resp,
              entry_maker = entry_maker.gen_from_notification {
                show_repo_info = not opts.repo,
              },
            },
            sorter = conf.generic_sorter(opts),
            previewer = previewers.issue.new(opts),
            attach_mappings = function(_, map)
              action_set.select:replace(function(prompt_bufnr, type)
                open(type)(prompt_bufnr)
              end)
              map("i", cfg.picker_config.mappings.open_in_browser.lhs, open_in_browser())
              map("i", cfg.picker_config.mappings.copy_url.lhs, copy_url())
              map("i", cfg.mappings.notification.read.lhs, mark_notification_read())
              return true
            end,
          })
          :find()
      end
    end,
  }
end

--
-- Issue templates
--
function M.issue_templates(templates, cb)
  local opts = {
    preview_title = "",
    prompt_title = "Issue templates",
    results_title = "",
  }

  pickers
    .new(opts, {
      finder = finders.new_table {
        results = templates,
        entry_maker = entry_maker.gen_from_issue_templates(),
      },
      sorter = conf.generic_sorter(opts),
      previewer = previewers.issue_template.new {},
      attach_mappings = function()
        actions.select_default:replace(function(prompt_bufnr)
          local selected_template = action_state.get_selected_entry(prompt_bufnr)
          actions.close(prompt_bufnr)
          cb(selected_template.template)
        end)
        return true
      end,
    })
    :find()
end

function M.discussions(opts)
  opts = opts or {}

  if utils.is_blank(opts.repo) then
    opts.repo = utils.get_remote_name()
  end

  if opts.cb == nil then
    opts.cb = function(selected, _)
      local url = selected.obj.url
      navigation.open_in_browser_raw(url)
    end
  end

  local cfg = octo_config.values

  local replace = create_replace(opts.cb)

  local cb = function(output, stderr)
    if stderr and not utils.is_blank(stderr) then
      utils.error(stderr)
      return
    end

    local resp = utils.aggregate_pages(output, "data.repository.discussions.node")
    local discussions = resp.data.repository.discussions.nodes

    local max_number = -1
    for _, discussion in ipairs(discussions) do
      if #tostring(discussion.number) > max_number then
        max_number = #tostring(discussion.number)
      end
    end

    if #discussions == 0 then
      utils.error(string.format("There are no matching discussions in %s.", opts.repo))
      return
    end

    opts.preview_title = opts.preview_title or ""

    pickers
      .new(opts, {
        finder = finders.new_table {
          results = discussions,
          entry_maker = entry_maker.gen_from_discussions(max_number),
        },
        sorter = conf.generic_sorter(opts),
        previewer = previewers.discussion.new(opts),
        attach_mappings = function(_, map)
          action_set.select:replace(replace)
          map("i", cfg.picker_config.mappings.copy_url.lhs, copy_url())
          return true
        end,
      })
      :find()
  end

  local owner, name = utils.split_repo(opts.repo)
  local order_by = cfg.discussions.order_by
  local query = graphql "discussions_query"
  utils.info "Fetching discussions (this may take a while) ..."

  gh.graphql {
    query = query,
    fields = {
      owner = owner,
      name = name,
      states = { "OPEN" },
      orderBy = order_by.field,
      direction = order_by.direction,
    },
    paginate = true,
    jq = ".",
    opts = {
      cb = cb,
    },
  }
end

function M.milestones(opts)
  if opts.cb == nil then
    utils.error "Callback action on milestone is required"
    return
  end

  local repo = opts.repo or utils.get_remote_name()
  local owner, name = utils.split_repo(repo)
  local query = graphql "open_milestones_query"

  gh.graphql {
    query = query,
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

        local title_width = 0
        for _, milestone in ipairs(nodes) do
          title_width = math.max(title_width, #milestone.title)
        end

        local non_empty_descriptions = false
        for _, milestone in ipairs(nodes) do
          if not utils.is_blank(milestone.description) then
            non_empty_descriptions = true
            break
          end
        end

        pickers
          .new(vim.deepcopy(dropdown_opts), {
            finder = finders.new_table {
              results = nodes,
              entry_maker = entry_maker.gen_from_milestone(title_width, non_empty_descriptions),
            },
            sorter = conf.generic_sorter(opts),
            attach_mappings = function(_, map)
              actions.select_default:replace(function(prompt_bufnr)
                select {
                  bufnr = prompt_bufnr,
                  single_cb = function(selected)
                    opts.cb(selected[1])
                  end,
                  multiple_cb = nil,
                  get_item = function(selected)
                    return selected.milestone
                  end,
                }
              end)
              return true
            end,
          })
          :find()
      end,
    },
  }
end

M.picker = {
  actions = M.actions,
  assigned_labels = M.select_assigned_label,
  assignees = M.select_assignee,
  changed_files = M.changed_files,
  commits = M.commits,
  discussions = M.discussions,
  gists = M.gists,
  issue_templates = M.issue_templates,
  issues = M.issues,
  labels = M.select_label,
  notifications = M.notifications,
  pending_threads = M.pending_threads,
  project_cards = M.select_project_card,
  project_cards_v2 = M.not_implemented,
  project_columns = M.select_target_project_column,
  project_columns_v2 = M.not_implemented,
  prs = M.pull_requests,
  repos = M.repos,
  review_commits = M.review_commits,
  search = M.search,
  users = M.select_user,
  milestones = M.milestones,
}

return M
