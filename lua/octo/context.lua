local utils = require "octo.utils"
local reviews = require "octo.reviews"

local M = {}

-- Helper function to create context-aware wrappers for buffer operations.
local function create_buffer_wrapper(check_fn, error_message)
  ---@param cb fun(buffer: OctoBuffer): nil
  return function(cb)
    return function()
      local buffer = utils.get_current_buffer()
      if not buffer or (check_fn and not check_fn(buffer)) then
        utils.error(error_message)
        return
      end
      cb(buffer)
    end
  end
end

local function create_buffer_direct(check_fn, error_message)
  ---@param cb fun(buffer: OctoBuffer): nil
  return function(cb)
    local buffer = utils.get_current_buffer()
    if not buffer or (check_fn and not check_fn(buffer)) then
      utils.error(error_message)
      return
    end
    return cb(buffer)
  end
end

-- Thunk-returning guard wrappers (for mappings/callbacks)

M.within_octo_buffer = create_buffer_wrapper(nil, "Not an Octo buffer")
M.within_repo = create_buffer_wrapper(function(b)
  return b:isRepo()
end, "Not a Repository buffer")
M.within_issue = create_buffer_wrapper(function(b)
  return b:isIssue()
end, "Not an Issue buffer")
M.within_pr = create_buffer_wrapper(function(b)
  return b:isPullRequest()
end, "Not a Pull Request buffer")
M.within_discussion = create_buffer_wrapper(function(b)
  return b:isDiscussion()
end, "Not a Discussion buffer")
M.within_release = create_buffer_wrapper(function(b)
  return b:isRelease()
end, "Not a Release buffer")
M.within_review_thread = create_buffer_wrapper(function(b)
  return b:isReviewThread()
end, "Not a Review Thread buffer")
M.within_issue_or_pr = create_buffer_wrapper(function(b)
  return b:isPullRequest() or b:isIssue()
end, "Not an Issue or Pull Request buffer")

-- Direct-invoke variants (no thunk, for use in commands/functions)

M.with_octo_buffer = create_buffer_direct(nil, "Not an Octo buffer")
M.with_repo = create_buffer_direct(function(b)
  return b:isRepo()
end, "Not a Repository buffer")
M.with_issue = create_buffer_direct(function(b)
  return b:isIssue()
end, "Not an Issue buffer")
M.with_pr = create_buffer_direct(function(b)
  return b:isPullRequest()
end, "Not a Pull Request buffer")
M.with_discussion = create_buffer_direct(function(b)
  return b:isDiscussion()
end, "Not a Discussion buffer")
M.with_release = create_buffer_direct(function(b)
  return b:isRelease()
end, "Not a Release buffer")
M.with_review_thread = create_buffer_direct(function(b)
  return b:isReviewThread()
end, "Not a Review Thread buffer")
M.with_issue_or_pr = create_buffer_direct(function(b)
  return b:isPullRequest() or b:isIssue()
end, "Not an Issue or Pull Request buffer")

---@param cb fun(current_review: Review): nil
function M.within_review(cb)
  return function()
    local current_review = reviews.get_current_review()
    if not current_review then
      utils.error "Please start or resume a review first"
      return
    end
    cb(current_review)
  end
end

---@param cb fun(current_review: Review): nil
function M.with_review(cb)
  local current_review = reviews.get_current_review()
  if not current_review then
    utils.error "Please start or resume a review first"
    return
  end
  return cb(current_review)
end

---@param cb fun(comment: any, buffer: OctoBuffer): nil
function M.on_comment_in_buffer(cb)
  return M.within_octo_buffer(function(buffer)
    local comment = buffer:get_comment_at_cursor()
    if not comment then
      utils.error "No comment found at cursor"
      return
    end
    cb(comment, buffer)
  end)
end

---@param cb fun(comment: any): nil
function M.on_comment(cb)
  return M.on_comment_in_buffer(function(comment, _)
    cb(comment)
  end)
end

---@param cb fun(body: BodyMetadata, buffer: OctoBuffer): nil
function M.on_body_in_buffer(cb)
  return M.within_issue_or_pr(function(buffer)
    local body, start_line, end_line = buffer:get_body_at_cursor()
    if not body then
      utils.error "No body found at cursor"
      return
    end
    cb(body, buffer)
  end)
end

---@param cb fun(body: BodyMetadata): nil
function M.on_body(cb)
  return M.on_body_in_buffer(function(body, _)
    cb(body)
  end)
end

---@param cb fun(thread: ThreadMetadata, buffer: OctoBuffer): nil
function M.on_thread_in_buffer(cb)
  return M.within_pr(function(buffer)
    local thread = buffer:get_thread_at_cursor()
    if not thread then
      utils.error "No thread found at cursor"
      return
    end
    cb(thread, buffer)
  end)
end

---@param cb fun(thread: ThreadMetadata): nil
function M.on_thread(cb)
  return M.on_thread_in_buffer(function(thread, _)
    cb(thread)
  end)
end

---Convenience references

---@return OctoBuffer?
function M.get_current_buffer()
  return utils.get_current_buffer()
end

---@return Review?
function M.get_current_review()
  return reviews.get_current_review()
end

---@param bufnr integer
---@return OctoBuffer?
function M.buffer_at(bufnr)
  return octo_buffers[bufnr]
end

return M
