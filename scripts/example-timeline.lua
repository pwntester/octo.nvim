local gh = require "octo.gh"
local writers = require "octo.ui.writers"

---@type string
local now = "" .. os.date "!%Y-%m-%dT%H:%M:%SZ"

local me = gh.api.graphql { query = "query { viewer { login } }", jq = ".data.viewer.login", opts = { mode = "sync" } }
if me == nil then
  error "Failed to get viewer login"
end

local other = "octocat"

local bufnr = vim.api.nvim_get_current_buf()
writers.write_comment_deleted_event(bufnr, {
  __typename = "CommentDeletedEvent",
  actor = { login = me },
  createdAt = now,
  deletedCommentAuthor = { login = other },
})
writers.write_comment_deleted_event(bufnr, {
  __typename = "CommentDeletedEvent",
  actor = { login = other },
  createdAt = now,
  deletedCommentAuthor = { login = me },
})
