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
M.within_issue_or_pr = create_buffer_wrapper(function(b)
  return b:isPullRequest() or b:isIssue()
end, "Not an Issue or  Pull Request buffer")

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

---@param cb fun(comment: any): nil
function M.on_comment(cb)
  return M.within_octo_buffer(function(buffer)
    local comment = buffer:get_comment_at_cursor()
    if not comment then
      utils.error "No comment found at cursor"
      return
    end
    cb(comment)
  end)
end

return M
