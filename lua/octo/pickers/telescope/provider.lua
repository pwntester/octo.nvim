---@diagnostic disable
local gh = require "octo.gh"
local graphql = require "octo.gh.graphql"
local headers = require "octo.gh.headers"
local queries = require "octo.gh.queries"
local parser = require "octo.gh.parser"
local navigation = require "octo.navigation"
local previewers = require "octo.pickers.telescope.previewers"
local entry_maker = require "octo.pickers.telescope.entry_maker"
local reviews = require "octo.reviews"
local utils = require "octo.utils"
local octo_config = require "octo.config"
local notifications = require "octo.notifications"

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

local function open(command)
  ---@param prompt_bufnr integer
  return function(prompt_bufnr)
    ---@diagnostic disable-next-line: redundant-parameter
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
    ---@type integer
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
  ---@param prompt_bufnr integer
  return function(prompt_bufnr)
    ---@diagnostic disable-next-line: redundant-parameter
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
  ---@param prompt_bufnr integer
  return function(prompt_bufnr)
    ---@diagnostic disable-next-line: redundant-parameter
    local entry = action_state.get_selected_entry(prompt_bufnr)
    utils.copy_url(entry.obj.url)
  end
end

local function copy_sha()
  ---@param prompt_bufnr integer
  return function(prompt_bufnr)
    ---@diagnostic disable-next-line: redundant-parameter
    local entry = action_state.get_selected_entry(prompt_bufnr)
    -- Handle different entry structures
    local sha = entry.obj and entry.obj.sha or entry.value
    utils.copy_sha(sha)
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
local function create_replace(cb)
  return function(prompt_bufnr, _)
    local selected = action_state.get_selected_entry()
    actions.close(prompt_bufnr)
    cb(selected)
  end
end

---@param opts { repo: string, states: string[], cb: function }
function M.issues(opts)
  opts = opts or {}

  if not opts.states then
    opts.states = { "OPEN" }
  end

  local repo = utils.pop_key(opts, "repo")
  if utils.is_blank(repo) then
    repo = utils.get_remote_name()
  end

  if not repo then
    utils.error "Cannot find repo"
    return
  end

  local replace = opts.cb and create_replace(opts.cb) or open_buffer
  utils.pop_key(opts, "cb")

  local owner, name = utils.split_repo(repo)
  local cfg = octo_config.values

  utils.info "Fetching issues (this may take a while) ..."
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
      cb = function(output, stderr)
        if stderr and not utils.is_blank(stderr) then
          utils.error(stderr)
        elseif output then
          local resp = utils.aggregate_pages(output, "data.repository.issues.nodes")
          local issues = resp.data.repository.issues.nodes
          if #issues == 0 then
            utils.error(string.format("There are no matching issues in %s.", repo))
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
                map("i", cfg.picker_config.mappings.copy_sha.lhs, copy_sha())
                return true
              end,
            })
            :find()
        end
      end,
    },
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
  gh.api.graphql {
    query = queries.gists,
    F = { privacy = privacy },
    paginate = true,
    jq = ".",
    opts = {
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
    },
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

---@param opts { repo: string, states: string[], cb: function }
function M.pull_requests(opts)
  opts = opts or {}
  if not opts.states then
    opts.states = { "OPEN" }
  end

  local repo = utils.pop_key(opts, "repo")
  if utils.is_blank(repo) then
    repo = utils.get_remote_name()
  end

  if not repo then
    utils.error "Cannot find repo"
    return
  end

  local replace = opts.cb and create_replace(opts.cb) or open_buffer
  utils.pop_key(opts, "cb")

  local owner, name = utils.split_repo(repo)

  local cfg = octo_config.values

  utils.info "Fetching pull requests (this may take a while) ..."
  gh.api.graphql {
    query = queries.pull_requests,
    F = {
      owner = owner,
      name = name,
      base_ref_name = opts.baseRefName,
      head_ref_name = opts.headRefName,
      labels = opts.labels,
      states = opts.states,
      order_by = cfg.pull_requests.order_by,
    },
    jq = ".",
    paginate = true,
    opts = {
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
                map("i", cfg.picker_config.mappings.copy_sha.lhs, function(prompt_bufnr)
                  local entry = action_state.get_selected_entry(prompt_bufnr)
                  -- Fetch PR details to get the head SHA
                  utils.info "Fetching PR details for SHA..."
                  local owner, repo = entry.obj.repository.nameWithOwner:match "([^/]+)/(.+)"
                  gh.api.get {
                    "/repos/{owner}/{repo}/pulls/{pull_number}",
                    format = { owner = owner, repo = repo, pull_number = entry.obj.number },
                    opts = {
                      cb = gh.create_callback {
                        success = function(output)
                          local pr_data = vim.json.decode(output)
                          utils.copy_sha(pr_data.head.sha)
                        end,
                      },
                    },
                  }
                end)
                map("i", cfg.picker_config.mappings.merge_pr.lhs, merge_pull_request())
                return true
              end,
            })
            :find()
        end
      end,
    },
  }
end

--
-- COMMITS
--

---@param opts {repo: string, number: integer }
function M.commits(opts)
  -- TODO: graphql
  gh.api.get {
    "/repos/{repo}/pulls/{number}/commits",
    format = { repo = opts.repo, number = opts.number },
    paginate = true,
    opts = {
      cb = gh.create_callback {
        success = function(output)
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
              previewer = previewers.commit.new { repo = opts.repo },
              attach_mappings = function(_, map)
                action_set.select:replace(function(prompt_bufnr, type)
                  open_preview_buffer(type)(prompt_bufnr)
                end)
                map("i", octo_config.values.picker_config.mappings.copy_sha.lhs, copy_sha())
                map("i", octo_config.values.picker_config.mappings.copy_url.lhs, copy_url())
                return true
              end,
            })
            :find()
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
              attach_mappings = function(_, map)
                action_set.select:replace(function(prompt_bufnr)
                  local commit = action_state.get_selected_entry(prompt_bufnr)
                  local right = commit.value
                  local left = commit.parent
                  actions.close(prompt_bufnr)
                  callback(right, left)
                end)
                map("i", octo_config.values.picker_config.mappings.copy_sha.lhs, copy_sha())
                return true
              end,
            })
            :find()
        end,
      },
    },
  }
end

--
-- FILES
--

---@param opts {repo: string, number: integer}
function M.changed_files(opts)
  gh.api.get {
    "/repos/{repo}/pulls/{number}/files",
    format = { repo = opts.repo, number = opts.number },
    paginate = true,
    opts = {
      cb = gh.create_callback {
        success = function(output)
          local results = vim.json.decode(output)

          local max_additions = -1
          local max_deletions = -1
          for _, result in ipairs(results) do
            if result.additions > max_additions then
              max_additions = result.additions
            end
            if result.deletions > max_deletions then
              max_deletions = result.deletions
            end
          end

          pickers
            .new({}, {
              prompt_title = false,
              results_title = false,
              preview_title = false,
              finder = finders.new_table {
                results = results,
                entry_maker = entry_maker.gen_from_git_changed_files {
                  max_additions = max_additions,
                  max_deletions = max_deletions,
                },
              },
              sorter = conf.generic_sorter {},
              previewer = previewers.changed_files.new { repo = opts.repo, number = opts.number },
              attach_mappings = function()
                action_set.select:replace(function(prompt_bufnr, type)
                  open_preview_buffer(type)(prompt_bufnr)
                end)
                return true
              end,
            })
            :find()
        end,
      },
    },
  }
end

---
-- SEARCH
---

---@param prompt string[]
---@return { single_repo: boolean, prompt: string }
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

---@param prompt string
---@return integer
local function get_search_size(prompt)
  return gh.api.graphql {
    query = queries.search_count,
    fields = { prompt = prompt },
    jq = ".data.search.issueCount",
    opts = {
      mode = "sync",
    },
  }
end

local function create_repo_picker(repos, opts, max)
  local cfg = octo_config.values

  local finder
  if type(repos) == "function" then
    finder = finders.new_dynamic {
      fn = repos,
      entry_maker = entry_maker.gen_from_repo(max.nameWithOwner, max.forkCount, max.stargazerCount, false),
    }
  else
    finder = finders.new_table {
      results = repos,
      entry_maker = entry_maker.gen_from_repo(max.nameWithOwner, max.forkCount, max.stargazerCount, true),
    }
  end

  pickers
    .new(opts, {
      finder = finder,
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

local function repo_search(opts)
  opts.prompt = opts.prompt or ""

  local function repos(prompt)
    local full_prompt = opts.prompt

    if prompt then
      full_prompt = full_prompt .. " " .. prompt
    end

    if utils.is_blank(full_prompt) then
      return {}
    end

    local data = gh.api.graphql {
      query = queries.search,
      f = { prompt = full_prompt, type = "REPOSITORY" },
      F = { last = 50 },
      jq = ".data.search.nodes",
      opts = { mode = "sync" },
    }

    return vim.json.decode(data)
  end

  create_repo_picker(repos, opts, {
    nameWithOwner = 25,
    forkCount = 5,
    stargazerCount = 5,
  })
end

function M.search(opts)
  opts = opts or {}
  opts.type = opts.type or "ISSUE"
  if opts.static == nil then
    opts.static = octo_config.values.picker_config.search_static
  end

  if opts.type == "REPOSITORY" then
    repo_search(opts)
    return
  end

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

  local settings = opts.type == "ISSUE"
      and {
        previewer = previewers.issue,
        entry_maker = entry_maker.gen_from_issue,
        entry_maker_static = function(width)
          return entry_maker.gen_from_issue(width, not search.single_repo)
        end,
      }
    or {
      previewer = previewers.discussion,
      entry_maker = entry_maker.gen_from_discussion,
    }

  local replace = opts.cb and create_replace(opts.cb) or open_buffer

  local function requester()
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

        local output = gh.api.graphql {
          query = queries.search,
          fields = { prompt = _prompt, type = opts.type },
          jq = ".data.search.nodes",
          opts = { mode = "sync" },
        }
        vim.list_extend(results, vim.json.decode(output))
      end
      return results
    end
  end
  local finder = finders.new_dynamic {
    fn = requester(),
    entry_maker = settings.entry_maker(width),
  }
  if opts.static then
    local results = requester() ""
    finder = finders.new_table {
      results = results,
      entry_maker = settings.entry_maker_static(width),
    }
  end
  opts.preview_title = opts.preview_title or ""
  opts.prompt_title = opts.prompt_title or ""
  opts.results_title = opts.results_title or ""
  pickers
    .new(opts, {
      finder = finder,
      sorter = conf.generic_sorter(opts),
      previewer = settings.previewer.new(opts),
      attach_mappings = function(_, map)
        action_set.select:replace(replace)
        map("i", cfg.picker_config.mappings.open_in_browser.lhs, open_in_browser())
        map("i", cfg.picker_config.mappings.copy_url.lhs, copy_url())
        map("i", cfg.picker_config.mappings.copy_sha.lhs, function(prompt_bufnr)
          local entry = action_state.get_selected_entry(prompt_bufnr)
          if entry.obj.__typename == "PullRequest" then
            -- Fetch PR details to get the head SHA
            utils.info "Fetching PR details for SHA..."
            local owner, repo = entry.obj.repository.nameWithOwner:match "([^/]+)/(.+)"
            gh.api.get {
              "/repos/{owner}/{repo}/pulls/{pull_number}",
              format = { owner = owner, repo = repo, pull_number = entry.obj.number },
              opts = {
                cb = gh.create_callback {
                  success = function(output)
                    local pr_data = vim.json.decode(output)
                    utils.copy_sha(pr_data.head.sha)
                  end,
                },
              },
            }
          else
            utils.info "Copy SHA not available for this item type"
          end
        end)
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

function M.workflow_runs(workflow_runs, title, on_select_cb)
  pickers
    .new({}, {
      prompt_title = title or false,
      results_title = false,
      preview_title = false,
      finder = finders.new_table {
        results = workflow_runs,
        entry_maker = entry_maker.gen_from_workflow_run(),
      },
      sorter = conf.generic_sorter {},
      previewer = previewers.workflow_runs.new {},
      attach_mappings = function(_, map)
        actions.select_default:replace(function(prompt_bufnr)
          local selection = action_state.get_selected_entry(prompt_bufnr)
          actions.close(prompt_bufnr)
          on_select_cb(selection.value)
        end)
        local mappings = require("octo.config").values.mappings.runs

        map("i", mappings.rerun.lhs, function(prompt_bufnr)
          local selection = action_state.get_selected_entry(prompt_bufnr)
          local id = selection.value.id
          require("octo.workflow_runs").rerun { db_id = id }
        end)

        map("i", mappings.rerun_failed.lhs, function(prompt_bufnr)
          local selection = action_state.get_selected_entry(prompt_bufnr)
          local id = selection.value.id
          require("octo.workflow_runs").rerun { db_id = id, failed = true }
        end)

        map("i", mappings.cancel.lhs, function(prompt_bufnr)
          local selection = action_state.get_selected_entry(prompt_bufnr)
          local id = selection.value.id
          require("octo.workflow_runs").cancel(id)
          actions.close(prompt_bufnr)
        end)
        return true
      end,
    })
    :find()
end

---
-- PROJECTS
---

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

function M.select_label(opts)
  opts = opts or {}

  local cb = opts.cb
  local repo = opts.repo

  if not repo then
    repo = utils.get_remote_name()
  end
  local owner, name = utils.split_repo(repo)

  opts = vim.tbl_deep_extend("force", dropdown_opts, opts)

  local function create_picker(output)
    local labels = vim.json.decode(output)

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

  gh.api.graphql {
    query = queries.labels,
    F = { owner = owner, name = name },
    jq = ".data.repository.labels.nodes",
    opts = {
      cb = gh.create_callback {
        success = create_picker,
      },
    },
  }
end

function M.select_assigned_label(opts)
  opts = opts or {}
  local cb = opts.cb
  opts = vim.tbl_deep_extend("force", opts, dropdown_opts)

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
  end
  local F = { owner = buffer.owner, name = buffer.name, number = buffer.number }

  local function create_picker(output)
    local labels = vim.json.decode(output)

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

  gh.api.graphql {
    query = query,
    F = F,
    jq = ".data.repository." .. key .. ".labels.nodes",
    opts = {
      cb = gh.create_callback {
        success = create_picker,
      },
    },
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

    local output = gh.api.graphql {
      query = queries.users,
      F = { prompt = prompt },
      paginate = true,
      opts = { mode = "sync" },
    }
    if utils.is_blank(output) then
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
  local output = gh.api.graphql {
    query = queries[query_name],
    f = { owner = owner, name = name },
    paginate = true,
    jq = ".data.repository." .. node_name .. ".nodes",
    opts = { mode = "sync" },
  }
  if utils.is_blank(output) then
    return {}
  end

  return utils.get_flatten_pages(output)
end

local function get_assignable_users()
  return get_users("assignable_users", "assignableUsers")
end

local function get_mentionable_users()
  return get_users("mentionable_users", "mentionableUsers")
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
          if not selected_user or not selected_user.user then
            return
          end
          if not selected_user.user.teams then
            -- user
            cb(selected_user.user.id)
          else
            -- organization, pick a team
            pickers
              .new(opts, {
                prompt_title = false,
                results_title = false,
                preview_title = false,
                finder = finders.new_table {
                  results = selected_user.user.teams,
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
    },
  }
end

---@param opts? { repo? : string, cb? : function }
function M.releases(opts)
  opts = opts or {}
  opts.repo = opts.repo or utils.get_remote_name()

  opts.cb = opts.cb or function(selection)
    utils.get("release", selection.obj.tagName, opts.repo)
  end

  -- Create custom layout configuration

  local picker_opts = {
    layout_config = {
      width = 0.8,
      height = 0.9,
      preview_width = 0.65,
    },
  }

  gh.release.list {
    repo = opts.repo,
    json = "name,tagName,createdAt",
    opts = {
      cb = gh.create_callback {
        success = function(output)
          local results = vim.json.decode(output)

          if #results == 0 then
            local msg = "No releases found"
            if opts.repo then
              msg = msg .. " for " .. opts.repo
            else
              msg = msg .. " in the current repository"
            end
            utils.error(msg)
            return
          end

          pickers
            .new(picker_opts, {
              finder = finders.new_table {
                results = results,
                entry_maker = entry_maker.gen_from_release(opts),
              },
              sorter = conf.generic_sorter(opts),
              previewer = previewers.release.new(opts),
              attach_mappings = function(prompt_bufnr, map)
                map("i", "<C-y>", function()
                  local selection = action_state.get_selected_entry(prompt_bufnr)
                  gh.release.view {
                    selection.obj.tagName,
                    repo = selection.obj.repo,
                    json = "url",
                    jq = ".url",
                    opts = {
                      cb = gh.create_callback { success = utils.copy_url },
                    },
                  }
                  return true
                end)
                map("i", "<CR>", function()
                  local selection = action_state.get_selected_entry(prompt_bufnr)
                  local repo = opts.repo
                  actions.close(prompt_bufnr)

                  opts.cb(selection)

                  return true
                end)
                return true
              end,
            })
            :find()
        end,
      },
    },
  }
end

--
-- REPOS
--

function M.repos(opts)
  opts = opts or {}

  opts.preview_title = opts.preview_title or ""
  opts.prompt_title = opts.prompt_title or ""
  opts.results_title = opts.results_title or ""

  local cfg = octo_config.values

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

          create_repo_picker(repos, opts, {
            nameWithOwner = max_nameWithOwner,
            forkCount = max_forkCount,
            stargazerCount = max_stargazerCount,
          })
        end,
      },
    },
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
    ---@type Picker
    local current_picker = action_state.get_current_picker(prompt_bufnr)
    current_picker:delete_selection(function(selection)
      notifications.request_read_notification(selection.thread_id)
    end)
  end
end

local function mark_notification_done()
  return function(prompt_bufnr)
    ---@type Picker
    local current_picker = action_state.get_current_picker(prompt_bufnr)
    current_picker:delete_selection(function(selection)
      notifications.delete_notification(selection.thread_id)
    end)
  end
end

local function unsubscribe_notification()
  return function(prompt_bufnr)
    ---@type Picker
    local current_picker = action_state.get_current_picker(prompt_bufnr)
    current_picker:delete_selection(function(selection)
      notifications.unsubscribe_notification(selection.thread_id)
    end)
  end
end

---@class NotificationOpts
---@field repo string
---@field all boolean Whether to show all of the notifications including read ones
---@field since string ISO 8601 timestamp
---@field preview_title string
---@field prompt_title string
---@field results_title string

---@param opts NotificationOpts
function M.notifications(opts)
  opts = opts or {}

  opts.all = opts.all or false
  local cfg = octo_config.values

  local endpoint = "/notifications"
  if opts.repo then
    local owner, name = utils.split_repo(opts.repo)
    endpoint = string.format("/repos/%s/%s/notifications", owner, name)
  end
  opts.prompt_title = opts.repo and string.format("%s Notifications", opts.repo) or "Github Notifications"

  opts.preview_title = ""
  opts.results_title = ""

  local function create_notification_picker(output)
    local resp = vim.json.decode(output)

    if #resp == 0 then
      utils.info "There are no notifications"
      return
    end
    ---@type table<string, any>
    local cached_notification_infos = {}

    local function preview_fn(bufnr, entry)
      local number = entry.value ---@type string
      local owner, name = utils.split_repo(entry.repo)
      local kind = entry.kind
      local preview = notifications.get_preview_fn(kind)
      local cached_notification = cached_notification_infos[entry.ordinal]
      if cached_notification then
        preview(cached_notification, bufnr)
      end
      notifications.fetch_preview(owner, name, number, kind, function(obj)
        cached_notification_infos[entry.ordinal] = obj
        if not vim.api.nvim_buf_is_loaded(bufnr) then
          return
        end
        preview(obj, bufnr)
      end)
    end
    opts.preview_fn = preview_fn

    local function copy_notification_url(prompt_bufnr)
      local entry = action_state.get_selected_entry(prompt_bufnr)
      notifications.copy_notification_url(entry.obj)
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
        previewer = previewers.notification.new(opts),
        attach_mappings = function(_, map)
          action_set.select:replace(function(prompt_bufnr, type)
            open(type)(prompt_bufnr)
          end)
          map("i", cfg.picker_config.mappings.open_in_browser.lhs, open_in_browser())
          map("i", cfg.picker_config.mappings.copy_url.lhs, copy_notification_url)
          map("i", cfg.picker_config.mappings.copy_sha.lhs, function(prompt_bufnr)
            local entry = action_state.get_selected_entry(prompt_bufnr)
            if entry.obj.subject.type == "PullRequest" then
              -- Fetch PR details to get the head SHA
              utils.info "Fetching PR details for SHA..."
              local owner, repo = entry.obj.repository.full_name:match "([^/]+)/(.+)"
              local number = entry.obj.subject.url:match "%d+$"
              gh.api.get {
                "/repos/{owner}/{repo}/pulls/{pull_number}",
                format = { owner = owner, repo = repo, pull_number = number },
                opts = {
                  cb = gh.create_callback {
                    success = function(output)
                      local pr_data = vim.json.decode(output)
                      utils.copy_sha(pr_data.head.sha)
                    end,
                  },
                },
              }
            else
              utils.info "Copy SHA not available for this notification type"
            end
          end)
          map("i", cfg.mappings.notification.read.lhs, mark_notification_read())
          map("i", cfg.mappings.notification.done.lhs, mark_notification_done())
          map("i", cfg.mappings.notification.unsubscribe.lhs, unsubscribe_notification())
          return true
        end,
      })
      :find()
  end

  gh.api.get {
    endpoint,
    paginate = true,
    F = {
      all = opts.all,
      since = opts.since,
    },
    opts = {
      headers = { headers.diff },
      cb = gh.create_callback { success = create_notification_picker },
    },
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

---@param opts { repo: string, cb: function }
function M.discussions(opts)
  opts = opts or {}

  if utils.is_blank(opts.repo) then
    opts.repo = utils.get_remote_name()
  end

  local cfg = octo_config.values

  local replace = opts.cb and create_replace(opts.cb) or open_buffer

  local function create_discussion_picker(discussions)
    if #discussions == 0 then
      utils.error(string.format("There are no matching discussions in %s.", opts.repo))
      return
    end

    local max_number = -1
    for _, discussion in ipairs(discussions) do
      if #tostring(discussion.number) > max_number then
        max_number = #tostring(discussion.number)
      end
    end

    opts.preview_title = opts.preview_title or ""

    pickers
      .new(opts, {
        finder = finders.new_table {
          results = discussions,
          entry_maker = entry_maker.gen_from_discussion(max_number),
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
  utils.info "Fetching discussions (this may take a while) ..."

  gh.api.graphql {
    query = queries.discussions,
    fields = {
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
          create_discussion_picker(discussions)
        end,
      },
    },
  }
end

function M.milestones(opts)
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
            attach_mappings = function(_, _map)
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

function M.project_columns_v2(cb)
  local buffer = utils.get_current_buffer()
  if not buffer then
    return
  end

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

        local opts = {}
        pickers
          .new(vim.deepcopy(dropdown_opts), {
            finder = finders.new_table {
              results = results,
              entry_maker = entry_maker.gen_from_project_v2(),
            },
            sorter = conf.generic_sorter(opts),
            attach_mappings = function(_, _map)
              actions.select_default:replace(function(prompt_bufnr)
                select {
                  bufnr = prompt_bufnr,
                  single_cb = function(selected)
                    selected = selected[1]

                    vim.ui.select(selected.columns.options, {
                      prompt = "Select a field value: ",
                      format_item = function(item)
                        return item.name
                      end,
                    }, function(value)
                      cb(selected.id, selected.columns.id, value.id)
                    end)
                  end,
                  multiple_cb = nil,
                  get_item = function(selected)
                    return selected.project
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

function M.project_cards_v2(cb)
  local buffer = utils.get_current_buffer()
  if not buffer then
    return
  end

  local obj = buffer:isIssue() and buffer:issue() or buffer:pullRequest()
  local cards = obj.projectItems
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

---@type octo.PickerModule
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
  users = M.select_user,
  workflow_runs = M.workflow_runs,
}

return M
