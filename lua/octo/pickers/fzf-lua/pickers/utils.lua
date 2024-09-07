local utils = require "octo.utils"
local fzf_utils = require "fzf-lua.utils"

local M = {}

M.multi_dropdown_opts = {
  prompt = nil,
  winopts = {
    height = 15,
    width = 0.4,
  },
}

M.dropdown_opts = vim.tbl_deep_extend("force", M.multi_dropdown_opts, {
  fzf_opts = {
    ["--no-multi"] = "",
  },
})

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

--[[
  Gets a consistent prompt.

  @param title The original prompt title.
  @return A prompt smartly postfixed with "> ".

  > get_prompt(nil) == "> "
  > get_prompt("") == "> "
  > get_prompt("something") == "something> "
  > get_prompt("something else>") == "something else> "
  > get_prompt("penultimate thing > ") == "penultimate thing > "
  > get_prompt("last th> ing") == "last th> ing> "
]]
function M.get_prompt(title)
  if title == nil or title == "" then
    return "> "
  elseif string.match(title, ">$") then
    return title .. " "
  elseif not string.match(title, "> $") then
    return title .. "> "
  end

  return title
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
  local navigation = require "octo.navigation"
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

function M.color_string_with_hex(s, hexcol)
  local r, g, b = hexcol:match "#(..)(..)(..)"
  if not r or not g or not b then
    return
  end
  r, g, b = tonumber(r, 16), tonumber(g, 16), tonumber(b, 16)

  -- Foreground code?
  local escseq = ("[%d;2;%d;%d;%dm"):format(38, r, g, b)
  return ("%s%s%s"):format(escseq, s, fzf_utils.ansi_escseq.clear)
end

function M.pad_string(s, length)
  -- Make sure it's a string.
  local string_s = tostring(s)
  return string.format("%s%" .. (length - #string_s) .. "s", string_s, " ")
end

return M
