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

---@param opts? { repo: string, states: string[], cb: function }
function M.pull_requests(opts)
  local owner, name = utils.split_repo(utils.pop_key(opts, "repo") or utils.get_remote_name())
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

---@type octo.PickerModule
M.picker = {
  actions = M.actions,
  issues = M.issues,
  prs = M.pull_requests,
}

return M
