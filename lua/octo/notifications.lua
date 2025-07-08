local gh = require "octo.gh"
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
      headers = { "Accept: application/vnd.github+json" },
    },
  }
end

---@param thread_id string
function M.delete_notification(thread_id)
  local opts = {
    cb = gh.create_callback { success = function() end },
    headers = { "Accept: application/vnd.github.v3.diff" },
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
      headers = { "Accept: application/vnd.github+json" },
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

---@param bufnr integer
---@param owner string
---@param name string
---@param number string
---@param kind string
function M.populate_preview_buf(bufnr, owner, name, number, kind)
  ---@param query string
  ---@param fields table<string, string>
  ---@param jq string
  ---@param preview fun(obj: any, bufnr: integer): nil
  local function fetch_and_preview(query, fields, jq, preview)
    gh.api.graphql {
      query = query,
      fields = fields,
      jq = jq,
      opts = {
        cb = gh.create_callback {
          failure = utils.print_err,
          success = function(output)
            if not vim.api.nvim_buf_is_loaded(bufnr) then
              return
            end

            local ok, obj = pcall(vim.json.decode, output)
            if not ok then
              utils.error("Failed to parse preview data: " .. vim.inspect(output))
              return
            end

            preview(obj, bufnr)
          end,
        },
      },
    }
  end
  ---@type string, table<string, string>, string, fun(obj: any, bufnr: integer): nil
  local query, fields, jq, preview

  if kind == "issue" then
    query = graphql("issue_query", owner, name, number, _G.octo_pv2_fragment)
    fields = {}
    jq = ".data.repository.issue"
    preview = writers.issue_preview
  elseif kind == "pull_request" then
    query = graphql("pull_request_query", owner, name, number, _G.octo_pv2_fragment)
    fields = {}
    jq = ".data.repository.pullRequest"
    preview = writers.issue_preview
  elseif kind == "discussion" then
    query = queries.discussion
    fields = { owner = owner, name = name, number = number }
    jq = ".data.repository.discussion"
    preview = writers.discussion_preview
  elseif kind == "release" then
    -- GraphQL only accepts tags and release notifications give back IDs
    release.get_tag_from_release_id({ owner = owner, repo = name, release_id = number }, function(tag_name)
      query = queries.release
      fields = { owner = owner, name = name, tag = tag_name }
      jq = ".data.repository.release"
      preview = writers.release_preview
      fetch_and_preview(query, fields, jq, preview)
    end)
    return
  end
  fetch_and_preview(query, fields, jq, preview)
end

return M
