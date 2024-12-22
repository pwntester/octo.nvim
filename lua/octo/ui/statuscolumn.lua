local vim = vim

local M = {}

-- stylua: ignore
local corners = {
  top    = "┌╴",
  middle = "│ ",
  last   = "└╴",
  single = "[ ",
}

---@alias OctoSign {text: string, hl?: string}
---@alias OctoComment { from: number, to: number, dirty: boolean }
---@type table<number, OctoComment[]>
local comments = {}

function M.reset(buf)
  comments[buf] = nil
end

function M.add(bufnr, start_line, end_line, is_dirty)
  comments[bufnr] = comments[bufnr] or {}
  table.insert(comments[bufnr], { from = start_line, to = end_line, dirty = is_dirty })
end

--- Fixes octo's comment rendering to take wrapping into account
---@param buf number
---@param lnum number
---@param vnum number
---@param win number
---@return OctoSign?
function M.get_sign(buf, lnum, vnum, win)
  lnum = lnum - 1
  for _, s in ipairs(comments[buf] or {}) do
    if lnum >= s.from and lnum <= s.to then
      local height = vim.api.nvim_win_text_height(win, { start_row = s.from, end_row = s.to }).all
      local height_end = vim.api.nvim_win_text_height(win, { start_row = s.to, end_row = s.to }).all
      local corner = corners.middle
      if height == 1 then
        corner = corners.single
      elseif lnum == s.from and vnum == 0 then
        corner = corners.top
      elseif lnum == s.to and vnum == height_end - 1 then
        corner = corners.last
      end
      return { text = corner, hl = s.dirty and "OctoDirty" or "OctoStatusColumn" }
    end
  end
end

---@param sign OctoSign?
---@param len? number
function M.highlight(sign, len)
  sign = sign or { text = "" }
  len = len or 2
  local text = vim.fn.strcharpart(sign.text, 0, len) ---@type string
  text = text .. string.rep(" ", len - vim.fn.strchars(text))
  return sign.hl and ("%#" .. sign.hl .. "#" .. text .. "%*") or text
end

function M.statuscolumn()
  local win = vim.g.statusline_winid
  local buf = vim.api.nvim_win_get_buf(win)
  local components = { "", "" }

  local comment = M.get_sign(buf, vim.v.lnum, vim.v.virtnum, win)

  components[1] = M.highlight(comment)

  if vim.v.virtnum ~= 0 then
    components[2] = "%= "
  end

  return table.concat(components, "")
end

return M
