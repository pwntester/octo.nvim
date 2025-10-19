local utils = require "octo.utils"
local reviews = require "octo.reviews"

local M = {}

---@param cb fun(buffer: OctoBuffer): nil
function M.within_issue(cb)
  return function()
    local buffer = utils.get_current_buffer()
    if not buffer or not buffer:isIssue() then
      utils.error "Not an issue buffer"
      return
    end

    cb(buffer)
  end
end

---@param cb fun(buffer: OctoBuffer): nil
function M.within_pr(cb)
  return function()
    local buffer = utils.get_current_buffer()
    if not buffer or not buffer:isPullRequest() then
      utils.error "Not a pull request buffer"
      return
    end

    cb(buffer)
  end
end

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

---@param cb fun(buffer: OctoBuffer): nil
function M.within_octo_buffer(cb)
  return function()
    local buffer = utils.get_current_buffer()
    if not buffer then
      utils.error "Not an Octo buffer"
      return
    end
    cb(buffer)
  end
end

---@param cb fun(comment: any): nil
function M.on_comment(cb)
  return function()
    M.within_octo_buffer(function(buffer)
      local comment = buffer:get_comment_at_cursor()
      if not comment then
        utils.error "No comment found at cursor"
        return
      end

      cb(comment)
    end)
  end
end

return M
