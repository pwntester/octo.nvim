local gh = require "octo.gh"
local headers = require "octo.gh.headers"
local graphql = require "octo.gh.graphql"
local utils = require "octo.utils"
local writers = require "octo.ui.writers"
local queries = require "octo.gh.queries"
local release = require "octo.release"

local M = {}

---@param thread_id string
function M.request_read_notification(thread_id)
  gh.api.patch {
    "/notifications/threads/{id}",
    format = { id = thread_id },
    opts = {
      cb = gh.create_callback { success = function() end },
      headers = { headers.json },
    },
  }
end

---@param thread_id string
function M.delete_notification(thread_id)
  local opts = {
    cb = gh.create_callback { success = function() end },
    headers = { headers.diff },
  }
  gh.api.delete {
    "/notifications/threads/{id}",
    format = { id = thread_id },
    opts = opts,
  }
end

---@param thread_id string
function M.unsubscribe_notification(thread_id)
  gh.api.delete {
    "/notifications/threads/{id}/subscription",
    format = { id = thread_id },
    opts = {
      cb = gh.create_callback {
        success = function()
          M.request_read_notification(thread_id)
        end,
      },
      headers = { headers.json },
    },
  }
end

---@param notification octo.NotificationFromREST
function M.copy_notification_url(notification)
  local subject = notification.subject
  local url = not utils.is_blank(subject.latest_comment_url) and subject.latest_comment_url or subject.url

  gh.api.get {
    url,
    jq = ".html_url",
    opts = {
      cb = gh.create_callback { success = utils.copy_url },
    },
  }
end

---@param owner string
---@param name string
---@param number string
---@param kind string
---@param on_success fun(obj: any): nil
function M.fetch_preview(owner, name, number, kind, on_success)
  ---@param query string
  ---@param fields table<string, string>
  ---@param jq string
  local function inner_fetch(query, fields, jq)
    gh.api.graphql {
      query = query,
      fields = fields,
      jq = jq,
      opts = {
        cb = gh.create_callback {
          failure = utils.print_err,
          success = function(output)
            local ok, obj = pcall(vim.json.decode, output)
            if not ok then
              utils.error("Failed to parse preview data: " .. vim.inspect(output))
              return
            end
            on_success(obj)
          end,
        },
      },
    }
  end
  ---@type string, table<string, string>, string
  local query, fields, jq

  if kind == "issue" then
    query = graphql("issue_query", owner, name, number, _G.octo_pv2_fragment)
    fields = {}
    jq = ".data.repository.issue"
  elseif kind == "pull_request" then
    query = graphql("pull_request_query", owner, name, number, _G.octo_pv2_fragment)
    fields = {}
    jq = ".data.repository.pullRequest"
  elseif kind == "discussion" then
    query = queries.discussion
    fields = { owner = owner, name = name, number = number }
    jq = ".data.repository.discussion"
  elseif kind == "release" then
    -- GraphQL only accepts tags and release notifications give back IDs
    release.get_tag_from_release_id({ owner = owner, repo = name, release_id = number }, function(tag_name)
      query = queries.release
      fields = { owner = owner, name = name, tag = tag_name }
      jq = ".data.repository.release"
      inner_fetch(query, fields, jq)
    end)
    return
  end
  inner_fetch(query, fields, jq)
end

---@param kind string
---@return fun(obj: any, bufnr: integer): nil
function M.get_preview_fn(kind)
  ---@type fun(obj: any, bufnr: integer): nil
  local preview
  if kind == "issue" then
    preview = writers.issue_preview
  elseif kind == "pull_request" then
    preview = writers.issue_preview
  elseif kind == "discussion" then
    preview = writers.discussion_preview
  elseif kind == "release" then
    preview = writers.release_preview
  end

  return preview
end

return M
