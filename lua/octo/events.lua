--- Read-only notification events emitted by octo.nvim after operations complete.
--- Consumers listen via `vim.api.nvim_create_autocmd("User", { pattern = "Octo*", callback = ... })`.
--- These are fire-and-forget — they cannot mutate the data that was operated on.

---@alias OctoEventName
---  | "OctoBufferLoaded"
---  | "OctoBufferClosed"
---  | "OctoReviewOpened"
---  | "OctoReviewClosed"
---  | "OctoReviewSubmitted"
---  | "OctoReviewDiscarded"
---  | "OctoCommentAdded"
---  | "OctoCommentUpdated"
---  | "OctoCommentDeleted"

---@class OctoEventPayloads
---@field OctoBufferLoaded { bufnr: integer, kind: string, repo: string, number: number }
---@field OctoBufferClosed { bufnr: integer }
---@field OctoReviewOpened { review_id: string, pull_request: { number: number, repo: string } }
---@field OctoReviewClosed { review_id: string }
---@field OctoReviewSubmitted { review_id: string, action: string, body: string, pull_request: { number: number, repo: string } }
---@field OctoReviewDiscarded { review_id: string, pull_request: { number: number, repo: string } }
---@field OctoCommentAdded { comment_id: string, body: string, kind: string, repo: string, number: number }
---@field OctoCommentUpdated { comment_id: string, body: string, kind: string, repo: string }
---@field OctoCommentDeleted { comment_id: string, kind: string, repo: string }

local M = {}

--- A buffer for an Octo object (issue, PR, discussion, etc.) finished loading.
M.BUFFER_LOADED = "OctoBufferLoaded"
--- An Octo buffer was closed or cleaned up.
M.BUFFER_CLOSED = "OctoBufferClosed"
--- A review session was opened for a pull request.
M.REVIEW_OPENED = "OctoReviewOpened"
--- A review session was closed without submission.
M.REVIEW_CLOSED = "OctoReviewClosed"
--- A review (approve, comment, or request changes) was submitted.
M.REVIEW_SUBMITTED = "OctoReviewSubmitted"
--- A pending review was discarded.
M.REVIEW_DISCARDED = "OctoReviewDiscarded"
--- A comment was added to an issue, PR, or discussion.
M.COMMENT_ADDED = "OctoCommentAdded"
--- A comment was edited.
M.COMMENT_UPDATED = "OctoCommentUpdated"
--- A comment was deleted.
M.COMMENT_DELETED = "OctoCommentDeleted"

--- Emit a read-only notification via `User` autocommand.
--- @param name OctoEventName  One of the event constants on this module (e.g. `events.REVIEW_SUBMITTED`).
--- @param data table  Payload for the event. Shape depends on the event — see `OctoEventPayloads`.
function M.emit(name, data)
  vim.api.nvim_exec_autocmds("User", {
    pattern = name,
    data = data,
  })
end

return M
