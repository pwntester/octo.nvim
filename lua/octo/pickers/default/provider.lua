---@diagnostic disable
---Picker that uses vim.ui.select
local notify = require "octo.notify"
local utils = require "octo.utils"
local gh = require "octo.gh"
local queries = require "octo.gh.queries"
local octo_config = require "octo.config"

local M = {}

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

---@type octo.PickerModule
M.picker = {
  actions = M.actions,
  discussions = M.discussions,
  issues = M.issues,
  prs = M.pull_requests,
  releases = M.releases,
}

return M
