-- This module contains previewer functions for the mini.picker integration.
-- Each function takes an item from the picker and returns a table of strings
-- to be displayed in the preview window.
local writers = require "octo.ui.writers"
local utils = require "octo.utils"

local M = {}

-- Creates a preview for an issue or a pull request.
-- It uses a temporary buffer to format the content using the writers,
-- and then returns the lines from the buffer.
local function issue_preview(obj)
  local bufnr = vim.api.nvim_create_buf(false, true)
  local state = utils.get_displayed_state(obj.__typename == "Issue", obj.state, obj.stateReason)
  writers.write_title(bufnr, obj.title, 1)
  writers.write_details(bufnr, obj)
  writers.write_body(bufnr, obj)
  writers.write_state(bufnr, state:upper(), obj.number)
  local reactions_line = vim.api.nvim_buf_line_count(bufnr) - 1
  writers.write_block(bufnr, { "", "" }, reactions_line)
  writers.write_reactions(bufnr, obj.reactionGroups, reactions_line)
  vim.api.nvim_buf_set_option(bufnr, "filetype", "octo")
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  vim.api.nvim_buf_delete(bufnr, { force = true })
  return lines
end

-- Previewer for issues.
M.issue = function(item)
  if item and item.data then
    return issue_preview(item.data)
  end
  return { "No data to preview" }
end

-- Previewer for pull requests.
-- It uses the same preview as issues.
M.pr = function(item)
  if item and item.data then
    return issue_preview(item.data)
  end
  return { "No data to preview" }
end

-- Previewer for changed files.
M.changed_file = function(item)
  if item and item.data and item.data.patch then
    return vim.split(item.data.patch, "\n")
  end
  return { "No patch available for this file." }
end

-- Previewer for search results.
M.search = function(item)
  if item and item.data and (item.type == "ISSUE" or item.type == "PULL_REQUEST") then
    return issue_preview(item.data)
  end
  return { "No preview available for this item type." }
end

-- Creates a preview for a discussion.
local function discussion_preview(obj)
  local bufnr = vim.api.nvim_create_buf(false, true)
  local state = obj.closed and "CLOSED" or "OPEN"
  writers.write_title(bufnr, tostring(obj.title), 1)
  writers.write_state(bufnr, state, obj.number)
  writers.write_discussion_details(bufnr, obj)
  writers.write_body(bufnr, obj, 13)

  if obj.answer ~= vim.NIL then
    local line = vim.api.nvim_buf_line_count(bufnr) + 1
    writers.write_discussion_answer(bufnr, obj, line)
  end

  vim.api.nvim_buf_set_option(bufnr, "filetype", "octo")
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  vim.api.nvim_buf_delete(bufnr, { force = true })
  return lines
end

-- Previewer for discussions.
M.discussion = function(item)
  if item and item.data then
    return discussion_preview(item.data)
  end
  return { "No data to preview" }
end

return M
