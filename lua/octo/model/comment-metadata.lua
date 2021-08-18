local M = {}

---@class CommentMetadata
---@field id string
---@field author string
---@field savedBody string
---@field body string
---@field dirty boolean
---@field extmark integer
---@field startLine integer
---@field endLine integer
---@field namespace integer
---@field reactionGroups table[]
---@field reactionLine integer
---@field viewerCanUpdate boolean
---@field viewerCanDelete boolean
---@field viewerDidAuthor boolean
---@field kind string
---@field replyTo string
---@field reviewId string
---@field path string
---@field diffSide string
---@field snippetStartLine integer
---@field snippetEndLine integer
local CommentMetadata = {}
CommentMetadata.__index = CommentMetadata

---CommentMetadata constructor.
---@return CommentMetadata
function CommentMetadata:new(opts)
  local this = {
    author = opts.author,
    id = opts.id,
    dirty = opts.dirty or false,
    savedBody = opts.body,
    body = opts.body,
    extmark = opts.extmark,
    namespace = opts.namespace,
    viewerCanUpdate = opts.viewerCanUpdate,
    viewerCanDelete = opts.viewerCanDelete,
    viewerDidAuthor = opts.viewerDidAuthor,
    reactionLine = opts.reactionLine,
    reactionGroups = opts.reactionGroups,
    kind = opts.kind,
    replyTo = opts.replyTo,
    reviewId = opts.pullRequestReview,
    path = opts.path,
    diffSide = opts.diffSide,
    snippetStartLine = opts.snippetStartLine,
    snippetEndLine = opts.snippetEndLine,
  }
  setmetatable(this, self)
  return this
end

M.CommentMetadata = CommentMetadata

return M
