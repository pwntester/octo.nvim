local backend = require "octo.backend"
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
      val = vim.fn.json_encode(val)
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
    utils.get(selection.kind, selection.repo, selection.value)
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

--
-- ISSUES
--
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

  opts.open = open
  opts.open_in_browser = open_in_browser
  opts.copy_url = copy_url

  local func = backend.get_funcs()["telescope_issues"]
  func(opts, octo_config.values, filter)
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

  opts.open_gist = open_gist

  local func = backend.get_funcs()["telescope_gists"]
  func(opts, privacy)
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

  opts.open = open
  opts.checkout_pull_request = checkout_pull_request
  opts.open_in_browser = open_in_browser
  opts.copy_url = copy_url
  opts.merge_pull_request = merge_pull_request

  local func = backend.get_funcs()["telescope_pull_requests"]
  func(opts, octo_config.values, filter)
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
  local func = backend.get_funcs()["telescope_commits"]
  func(buffer, open_preview_buffer)
end

function M.review_commits(cb)
  local current_review = require("octo.reviews").get_current_review()
  if not current_review then
    utils.error "No review in progress"
    return
  end
  local func = backend.get_funcs()["telescope_review_commits"]
  func(current_review, cb)
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
  local func = backend.get_funcs()["telescope_changed_files"]
  func(buffer, open_preview_buffer)
end

---
-- SEARCH
---
function M.search(opts)
  opts = opts or {}
  local cfg = octo_config.values
  local requester = function()
    return function(prompt)
      if not opts.prompt and utils.is_blank(prompt) then
        return {}
      end
      if type(opts.prompt) == "string" then
        opts.prompt = { opts.prompt }
      end
      local results = {}
      for _, val in ipairs(opts.prompt) do
        local _prompt = prompt
        if val then
          _prompt = string.format("%s %s", val, _prompt)
        end
        local func = backend.get_funcs()["telescope_search"]
        local output = func(_prompt)
        if output then
          local resp = vim.fn.json_decode(output)
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
  pickers
    .new(opts, {
      finder = finder,
      sorter = conf.generic_sorter(opts),
      previewer = previewers.issue.new(opts),
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
  local func = backend.get_funcs()["telescope_select_target_project_column"]
  func(buffer, dropdown_opts, cb)
end

--
-- LABELS
--
function M.select_label(cb)
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer then
    return
  end
  local func = backend.get_funcs()["telescope_select_label"]
  func(buffer, dropdown_opts, cb)
end

function M.select_assigned_label(cb)
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer then
    return
  end
  local func = backend.get_funcs()["telescope_select_assigned_label"]
  func(buffer, dropdown_opts, cb)
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

      local func = backend.get_funcs()["telescope_get_users"]
      local output = func(prompt)
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

  pickers
    .new(opts, {
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
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer then
    return
  end

  local func = backend.get_funcs()["telescope_select_assignee"]
  func(buffer, dropdown_opts, cb)
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
      local remote_hostname = utils.get_remote_host()
      local func = backend.get_funcs()["get_user_name"]
      opts.login = func(remote_hostname)
    end
  end
  opts.open = open
  opts.open_in_browser = open_in_browser
  opts.copy_url = copy_url

  local func = backend.get_funcs()["telescope_repos"]
  func(opts, octo_config.values)
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

  pickers
    .new(opts, {
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
    })
    :find()
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

M.picker = {
  issues = M.issues,
  prs = M.pull_requests,
  gists = M.gists,
  commits = M.commits,
  review_commits = M.review_commits,
  changed_files = M.changed_files,
  pending_threads = M.pending_threads,
  project_cards = M.select_project_card,
  project_cards_v2 = M.not_implemented,
  project_columns = M.select_target_project_column,
  project_columns_v2 = M.not_implemented,
  labels = M.select_label,
  assigned_labels = M.select_assigned_label,
  users = M.select_user,
  assignees = M.select_assignee,
  repos = M.repos,
  search = M.search,
  actions = M.actions,
  issue_templates = M.issue_templates,
}

return M
