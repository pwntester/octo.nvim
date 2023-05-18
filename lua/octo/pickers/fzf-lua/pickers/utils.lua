local navigation = require "octo.navigation"
local utils = require "octo.utils"

local M = {}

M.dropdown_opts = {
  prompt = nil,
  winopts = {
    height = 15,
    width = 0.4,
  },
  fzf_opts = {
    ["--no-multi"] = "",
  },
}

function M.get_filter(opts, kind)
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

--[[
  Open the entry in a buffer.

  @param command One of 'default', 'horizontal', 'vertial', or 'tab'
  @param entry The entry to open.
]]
function M.open(command, entry)
  if command == "default" then
    vim.cmd [[:buffer %]]
  elseif command == "horizontal" then
    vim.cmd [[:sbuffer %]]
  elseif command == "vertical" then
    vim.cmd [[:vert sbuffer %]]
  elseif command == "tab" then
    vim.cmd [[:tab sb %]]
  end
  utils.get(entry.kind, entry.repo, entry.value)
end

-- TODO this might not be possible with fzf-lua. Preview buffers are not
-- retained at all.
function M.open_preview_buffer(command, bufnr, entry)
  if command == "default" then
    vim.cmd(string.format(":buffer %d", bufnr))
  elseif command == "horizontal" then
    vim.cmd(string.format(":sbuffer %d", bufnr))
  elseif command == "vertical" then
    vim.cmd(string.format(":vert sbuffer %d", bufnr))
  elseif command == "tab" then
    vim.cmd(string.format(":tab sb %d", bufnr))
  end

  vim.cmd [[stopinsert]]
end

--[[
  Opens the entry in your default browser.

  @param entry The entry to open.
]]
function M.open_in_browser(entry)
  local number
  local repo = entry.repo
  if entry.kind ~= "repo" then
    number = entry.value
  end
  navigation.open_in_browser(entry.kind, repo, number)
end

--[[
  Copies the url to the clipboard.

  @param entry The entry to get the url from.
]]
function M.copy_url(entry)
  local url = entry.obj.url
  vim.fn.setreg("+", url, "c")
  utils.info("Copied '" .. url .. "' to the system clipboard (+ register)")
end

return M
