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
        local max_number = -1
        for _, issue in ipairs(issues) do
          if issue.number > max_number then
            max_number = issue.number
          end
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
            ret[#ret + 1] = utils.get_icon { kind = item.kind, obj = item }
            ret[#ret + 1] = { string.format("#%d", item.number), "Comment" }
            ret[#ret + 1] = { (" "):rep(#tostring(max_number) - #tostring(item.number) + 1) }
            ret[#ret + 1] = { item.title, "Normal" }
            return ret
          end,
          win = {
            input = {
              keys = {
                [cfg.picker_config.mappings.open_in_browser.lhs] = { "open_in_browser", mode = { "n", "i" } },
                [cfg.picker_config.mappings.copy_url.lhs] = { "copy_url", mode = { "n", "i" } },
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
          if pull.number > max_number then
            max_number = pull.number
          end
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
            ret[#ret + 1] = utils.get_icon { kind = item.kind, obj = item }
            ret[#ret + 1] = { string.format("#%d", item.number), "Comment" }
            ret[#ret + 1] = { (" "):rep(#tostring(max_number) - #tostring(item.number) + 1) }
            ret[#ret + 1] = { item.title, "Normal" }
            return ret
          end,
          win = {
            input = {
              keys = {
                [cfg.picker_config.mappings.open_in_browser.lhs] = { "open_in_browser", mode = { "n", "i" } },
                [cfg.picker_config.mappings.copy_url.lhs] = { "copy_url", mode = { "n", "i" } },
                [cfg.picker_config.mappings.checkout_pr.lhs] = { "check_out_pr", mode = { "n", "i" } },
                [cfg.picker_config.mappings.merge_pr.lhs] = { "merge_pr", mode = { "n", "i" } },
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
        local notifications = vim.json.decode(output)

        if #notifications == 0 then
          utils.info "There are no notifications"
          return
        end

        local safe_notifications = {}

        for _, notification in ipairs(notifications) do
          local safe = false
          notification.subject.number = notification.subject.url:match "%d+$"
          notification.text = string.format("#%d %s", notification.subject.number, notification.subject.title)
          notification.kind = notification.subject.type:lower()
          if notification.kind == "pullrequest" then
            notification.kind = "pull_request"
          end
          notification.status = notification.unread and "unread" or "read"
          if notification.kind == "issue" then
            notification.file = utils.get_issue_uri(notification.subject.number, notification.repository.full_name)
            safe = true
          elseif notification.kind == "pull_request" then
            notification.file =
              utils.get_pull_request_uri(notification.subject.number, notification.repository.full_name)
            safe = true
          end
          if safe then
            safe_notifications[#safe_notifications + 1] = notification
          end
        end

        Snacks.picker.pick {
          title = opts.preview_title or "",
          items = safe_notifications,
          format = function(item, _)
            ---@type snacks.picker.Highlight[]
            local ret = {}
            ---@diagnostic disable-next-line: assign-type-mismatch
            ret[#ret + 1] = utils.icons.notification[item.kind][item.status]
            ret[#ret + 1] = { string.format("#%d", item.subject.number), "Comment" }
            ret[#ret + 1] = { " " }
            ret[#ret + 1] = { item.repository.full_name, "Function" }
            ret[#ret + 1] = { " " }
            ret[#ret + 1] = { item.subject.title, "Normal" }
            return ret
          end,
          win = {
            input = {
              keys = {
                [cfg.picker_config.mappings.open_in_browser.lhs] = { "open_in_browser", mode = { "n", "i" } },
                [cfg.picker_config.mappings.copy_url.lhs] = { "copy_url", mode = { "n", "i" } },
                [cfg.mappings.notification.read.lhs] = { "mark_notification_read", mode = { "n", "i" } },
              },
            },
          },
          actions = {
            open_in_browser = function(_picker, item)
              navigation.open_in_browser(item.kind, item.repository.full_name, item.subject.number)
            end,
            copy_url = function(_picker, item)
              local url = item.url
              vim.fn.setreg("+", url, "c")
              utils.info("Copied '" .. url .. "' to the system clipboard (+ register)")
            end,
            mark_notification_read = function(picker, item)
              local url = string.format("/notifications/threads/%s", item.id)
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
              -- TODO: No current way to redraw the list/remove just this item
              picker:close()
              M.notifications(opts)
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
  notifications = M.notifications,
  pending_threads = M.not_implemented,
  project_cards = M.not_implemented,
  project_cards_v2 = M.not_implemented,
  project_columns = M.not_implemented,
  project_columns_v2 = M.not_implemented,
  prs = M.pull_requests,
  repos = M.not_implemented,
  workflow_runs = M.not_implemented,
  review_commits = M.not_implemented,
  search = M.not_implemented,
  users = M.not_implemented,
  milestones = M.not_implemented,
}

return M
