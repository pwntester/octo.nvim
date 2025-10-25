---@diagnostic disable
local navigation = require "octo.navigation"
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

---Open the entry in a buffer.
---
---@param command 'default' |'horizontal' | 'vertical' | 'tab'
---@param entry table
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

  if not entry.kind then
    local buf = vim.api.nvim_create_buf(false, true)

    if entry.author and entry.ordinal then
      local lines = {}

      vim.list_extend(lines, { string.format("Commit: %s", entry.value) })
      vim.list_extend(lines, { string.format("Author: %s", entry.author) })
      vim.list_extend(lines, { string.format("Date: %s", entry.date) })
      vim.list_extend(lines, { "" })
      vim.list_extend(lines, vim.split(entry.msg, "\n"))
      vim.list_extend(lines, { "" })

      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

      vim.api.nvim_buf_set_option(buf, "filetype", "git")

      vim.api.nvim_buf_add_highlight(buf, -1, "OctoDetailsLabel", 0, 0, string.len "Commit:")
      vim.api.nvim_buf_add_highlight(buf, -1, "OctoDetailsLabel", 1, 0, string.len "Author:")
      vim.api.nvim_buf_add_highlight(buf, -1, "OctoDetailsLabel", 2, 0, string.len "Date:")

      local url = string.format("/repos/%s/commits/%s", entry.repo, entry.value)
      local cmd =
        table.concat({ "gh", "api", "--paginate", url, "-H", "'Accept: application/vnd.github.v3.diff'" }, " ")
      local proc = io.popen(cmd, "r")
      local output ---@type string
      if proc ~= nil then
        output = proc:read "*a"
        proc:close()
      else
        output = "Failed to read from " .. url
      end

      vim.api.nvim_buf_set_lines(buf, #lines, -1, false, vim.split(output, "\n"))
    end

    if entry.change and entry.change.patch then
      local diff = entry.change.patch
      if diff then
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(diff, "\n"))
        vim.api.nvim_buf_set_option(buf, "filetype", "diff")
      end
    end

    vim.api.nvim_win_set_buf(0, buf)
    return
  end

  utils.get(entry.kind, entry.value, entry.repo)
end

---Gets a consistent prompt.
---
---@param title string The original prompt title.
---@return string prompt A prompt smartly postfixed with "> ".
---
---> get_prompt(nil) == "> "
---> get_prompt("") == "> "
---> get_prompt("something") == "something> "
---> get_prompt("something else>") == "something else> "
---> get_prompt("penultimate thing > ") == "penultimate thing > "
---> get_prompt("last th> ing") == "last th> ing> "
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

---Opens the entry in your default browser.
---
---@param entry table
function M.open_in_browser(entry)
  local number ---@type integer
  local repo = entry.repo
  if entry.kind ~= "repo" then
    number = entry.value
  end
  navigation.open_in_browser(entry.kind, repo, number)
end

---Copies the entry url to the clipboard.
---
---@param entry table
function M.copy_url(entry)
  utils.copy_url(entry.obj.url)
end

---@param s string
---@param hexcol string
---@return string|nil
function M.color_string_with_hex(s, hexcol)
  local r, g, b = hexcol:match "#(..)(..)(..)"
  if not r or not g or not b then
    return
  end
  r, g, b = tonumber(r, 16), tonumber(g, 16), tonumber(b, 16)

  -- Foreground code?
  local escseq = ("\27[%d;2;%d;%d;%dm"):format(38, r, g, b) -- \27 is the escape code of ctrl-[ and <esc>
  return ("%s%s%s"):format(escseq, s, fzf_utils.ansi_escseq.clear)
end

---@param s unknown
---@param length integer
---@return string
function M.pad_string(s, length)
  local string_s = tostring(s)
  return string.format("%s%" .. (length - #string_s) .. "s", string_s, " ")
end

return M
