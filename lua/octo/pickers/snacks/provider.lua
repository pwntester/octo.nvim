local gh = require "octo.gh"
local graphql = require "octo.gh.graphql"
local utils = require "octo.utils"
local octo_config = require "octo.config"
local navigation = require "octo.navigation"

local M = {}

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

function M.not_implemented()
  utils.error "Not implemented yet"
end

M.issues = function(opts)
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
        for _, issue in ipairs(issues) do
          issue.text = string.format("#%d %s", issue.number, issue.title)
          issue.file = utils.get_issue_uri(issue.number, issue.repository.nameWithOwner)
          issue.kind = issue.__typename:lower()
        end

        Snacks.picker.pick {
          title = opts.preview_title or "",
          items = issues,
          format = function(item, _)
            ---@type snacks.picker.Highlight[]
            local ret = {}
            ---@diagnostic disable-next-line: assign-type-mismatch
            ret[#ret + 1] = utils.icons[item.kind][item.state:lower()]
            ret[#ret + 1] = { string.format("#%d", item.number), "Comment" }
            ret[#ret + 1] = { " " }
            ret[#ret + 1] = { item.title, "Normal" }
            return ret
          end,
          win = {
            input = {
              keys = {
                [cfg.picker_config.mappings.open_in_browser.lhs] = { "open_in_browser", mode = "i" },
                [cfg.picker_config.mappings.copy_url.lhs] = { "copy_url", mode = "i" },
              },
            },
          },
          actions = {
            open_in_browser = function(_picker, item)
              navigation.open_in_browser(item.kind, item.repository.nameWithOwner, item.number)
            end,
            copy_url = function(_picker, item)
              local url = item.url
              vim.fn.setreg("+", url, "c")
              utils.info("Copied '" .. url .. "' to the system clipboard (+ register)")
            end,
          },
        }
      end
    end,
  }
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
          pull.text = string.format("#%d %s", pull.number, pull.title)
          pull.file = utils.get_pull_request_uri(pull.number, pull.repository.nameWithOwner)
          pull.kind = pull.__typename:lower() == "pullrequest" and "pull_request" or "unknown"
        end

        Snacks.picker.pick {
          title = opts.preview_title or "",
          items = pull_requests,
          format = function(item, _)
            ---@type snacks.picker.Highlight[]
            local ret = {}
            ---@diagnostic disable-next-line: assign-type-mismatch
            ret[#ret + 1] = utils.icons[item.kind][item.state:lower()]
            ret[#ret + 1] = { string.format("#%d", item.number), "Comment" }
            ret[#ret + 1] = { " " }
            ret[#ret + 1] = { item.title, "Normal" }
            return ret
          end,
          win = {
            input = {
              keys = {
                [cfg.picker_config.mappings.open_in_browser.lhs] = { "open_in_browser", mode = "i" },
                [cfg.picker_config.mappings.copy_url.lhs] = { "copy_url", mode = "i" },
                [cfg.picker_config.mappings.checkout_pr.lhs] = { "check_out_pr", mode = "i" },
                [cfg.picker_config.mappings.merge_pr.lhs] = { "merge_pr", mode = "i" },
              },
            },
          },
          actions = {
            open_in_browser = function(_picker, item)
              navigation.open_in_browser(item.kind, item.repository.nameWithOwner, item.number)
            end,
            copy_url = function(_picker, item)
              local url = item.url
              vim.fn.setreg("+", url, "c")
              utils.info("Copied '" .. url .. "' to the system clipboard (+ register)")
            end,
            check_out_pr = function(_picker, _item)
              M.not_implemented()
            end,
            merge_pr = function(_picker, _item)
              M.not_implemented()
            end,
          },
        }
      end
    end,
  }
end

M.picker = {
  actions = M.not_implemented,
  assigned_labels = M.not_implemented,
  assignees = M.not_implemented,
  changed_files = M.not_implemented,
  commits = M.not_implemented,
  discussions = M.not_implemented,
  gists = M.not_implemented,
  issue_templates = M.not_implemented,
  issues = M.issues,
  labels = M.not_implemented,
  pending_threads = M.not_implemented,
  project_cards = M.not_implemented,
  project_cards_v2 = M.not_implemented,
  project_columns = M.not_implemented,
  project_columns_v2 = M.not_implemented,
  prs = M.pull_requests,
  repos = M.not_implemented,
  review_commits = M.not_implemented,
  search = M.not_implemented,
  users = M.not_implemented,
  milestones = M.not_implemented,
}

return M
