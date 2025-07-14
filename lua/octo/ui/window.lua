local utils = require "octo.utils"
local M = {}

---@class octo.BorderHeaderFloatOpts
---@field width integer
---@field border_width integer
---@field padding integer
---@field header string?
---@field header_height integer
---@field height integer
---@field y_offset integer
---@field x_offset integer

---@param opts octo.BorderHeaderFloatOpts
function M.create_border_header_float(opts)
  local outer_winid, outer_bufnr
  outer_bufnr = vim.api.nvim_create_buf(false, true)
  local outer = {}
  local line_fill = string.rep("─", opts.width - 2 * opts.border_width)
  table.insert(outer, string.format("┌%s┐", line_fill))
  if opts.header then
    local trimmed_header = string.sub(opts.header, 1, opts.width - 2 * opts.border_width - 2 * opts.padding)
    local fill =
      string.rep(" ", opts.width - 2 * opts.padding - 2 * opts.border_width - vim.fn.strdisplaywidth(trimmed_header))
    table.insert(outer, string.format("│ %s%s │", trimmed_header, fill))
    table.insert(outer, string.format("├%s┤", line_fill))
    for _ = 1, opts.height - 2 * opts.border_width - 2 * opts.header_height do
      table.insert(outer, string.format("│%s│", string.rep(" ", opts.width - 2 * opts.border_width)))
    end
  else
    for _ = 1, opts.height - 2 * opts.border_width do
      table.insert(outer, string.format("│%s│", line_fill))
    end
  end
  table.insert(outer, string.format("└%s┘", line_fill))
  vim.api.nvim_buf_set_lines(outer_bufnr, 0, -1, false, outer)
  outer_winid = vim.api.nvim_open_win(outer_bufnr, false, {
    relative = "editor",
    row = opts.y_offset,
    col = opts.x_offset,
    width = opts.width,
    height = opts.height,
    focusable = false,
  })
  vim.bo[outer_bufnr].modifiable = false
  vim.wo[outer_winid].foldcolumn = "0"
  vim.wo[outer_winid].signcolumn = "no"
  vim.wo[outer_winid].number = false
  vim.wo[outer_winid].relativenumber = false
  vim.wo[outer_winid].cursorline = false
  return outer_winid
end

---@class octo.ContentFloatOpts
---@field content? string[]
---@field header boolean
---@field header_height integer
---@field x_offset integer
---@field y_offset integer
---@field width integer
---@field height integer
---@field border_width integer
---@field padding integer

---@param opts octo.ContentFloatOpts
function M.create_content_float(opts)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, opts.content or {})
  local winid = vim.api.nvim_open_win(bufnr, true, {
    relative = "editor",
    row = opts.header and (opts.y_offset + 2 * opts.border_width + opts.header_height)
      or (opts.y_offset + opts.border_width),
    col = opts.x_offset + opts.border_width + opts.padding,
    width = opts.width - 2 * opts.border_width - 2 * opts.padding,
    height = opts.header and (opts.height - 3 * opts.border_width - 2 * opts.header_height)
      or (opts.height - 2 * opts.border_width),
    focusable = true,
  })
  vim.wo[winid].previewwindow = true
  vim.wo[winid].foldcolumn = "0"
  vim.wo[winid].signcolumn = "no"
  vim.wo[winid].number = false
  vim.wo[winid].relativenumber = false
  vim.wo[winid].cursorline = false
  return winid, bufnr
end

---@class octo.CenteredFloatOpts
---@field x_percent? number
---@field y_percent? number
---@field header? string
---@field content? string[]

---@param opts? octo.CenteredFloatOpts
---@return integer winid
---@return integer bufnr
function M.create_centered_float(opts)
  opts = opts or {}
  opts.x_percent = opts.x_percent or 0.6
  opts.y_percent = opts.y_percent or 0.4

  -- calculate vim height
  local vim_height = vim.o.lines - vim.o.cmdheight
  if vim.o.laststatus ~= 0 then
    vim_height = vim_height - 1
  end

  -- calculate vim width
  local vim_width = vim.o.columns

  -- calculate longest line in lines
  local max_line = -1
  if opts.content then
    for _, line in ipairs(opts.content) do
      max_line = math.max(vim.fn.strdisplaywidth(line), max_line)
    end
  end
  -- calculate window height/width
  local border_width = 1
  local padding = 1
  local header_height = 1
  local width ---@type integer
  local height ---@type integer
  if max_line > 0 then
    -- pre-defined content
    width = math.min(vim_width * 0.9, max_line + 2 * padding + 2 * border_width)
    if opts.header then
      height = math.min(vim_height, 3 * border_width + header_height + #opts.content) + 1
    else
      height = math.min(vim_height, 2 * border_width + #opts.content) + 1
    end

    width = math.floor(width)
    height = math.floor(height)
  else
    width = math.floor(vim_width * opts.x_percent)
    height = math.floor(vim_height * opts.y_percent)
  end
  -- calculate offsets
  local x_offset = math.floor((vim_width - width) / 2)
  local y_offset = math.floor((vim_height - height) / 2)

  -- outer win (header + border)
  local outer_winid = M.create_border_header_float {
    width = width,
    border_width = border_width,
    padding = padding,
    header = opts.header,
    header_height = header_height,
    height = height,
    y_offset = y_offset,
    x_offset = x_offset,
  }

  -- content win
  local winid, bufnr = M.create_content_float {
    content = opts.content,
    width = width,
    border_width = border_width,
    padding = padding,
    height = height,
    header = opts.header and true or false,
    header_height = header_height,
    y_offset = y_offset,
    x_offset = x_offset,
  }

  -- window binding
  local aucmd = string.format(
    "autocmd BufLeave,BufDelete <buffer=%d> :lua require('octo.ui.window').try_close_wins(%d, %d)",
    bufnr,
    winid,
    outer_winid
  )
  vim.cmd(aucmd)

  -- mappings
  local mapping_opts = { script = true, silent = true, noremap = true, buffer = bufnr, desc = "Close window" }
  vim.keymap.set("n", "<C-c>", function()
    require("octo.ui.window").try_close_wins(winid, outer_winid)
  end, mapping_opts)
  return winid, bufnr
end

---@param ... integer
function M.try_close_wins(...)
  for _, win_id in ipairs { ... } do
    pcall(vim.api.nvim_win_close, win_id, true)
  end
end

---@class octo.PopupOpts
---@field width? number
---@field height? number
---@field bufnr integer

---@param opts? octo.PopupOpts
function M.create_popup(opts)
  local current_bufnr = vim.api.nvim_get_current_buf()
  opts = opts or {}
  if not opts.width then
    opts.width = 30
  end
  if not opts.height then
    opts.height = 10
  end

  local border_width = 1
  local popup_winid = vim.api.nvim_open_win(opts.bufnr, false, {
    relative = "cursor",
    anchor = "SW",
    row = -2,
    col = 2,
    focusable = false,
    style = "minimal",
    width = opts.width - 2 * border_width,
    height = opts.height - 2 * border_width,
  })

  local border = {}
  table.insert(border, string.format("┌%s┐", string.rep("─", opts.width - 2 * border_width)))
  for _ = 1, opts.height - 2 do
    table.insert(border, string.format("│%s│", string.rep(" ", opts.width - 2 * border_width)))
  end
  table.insert(border, string.format("└%s┘", string.rep("─", opts.width - 2 * border_width)))
  local border_bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(border_bufnr, 0, -1, false, border)
  local border_winid = vim.api.nvim_open_win(border_bufnr, false, {
    relative = "cursor",
    anchor = "SW",
    row = -1,
    col = 1,
    focusable = false,
    style = "minimal",
    width = opts.width,
    height = opts.height,
  })
  vim.wo[border_winid].foldcolumn = "0"
  vim.wo[border_winid].signcolumn = "no"
  vim.wo[border_winid].number = false
  vim.wo[border_winid].relativenumber = false

  utils.close_preview_autocmd({ "CursorMoved", "CursorMovedI", "WinLeave" }, border_winid, { current_bufnr })
  utils.close_preview_autocmd({ "CursorMoved", "CursorMovedI", "WinLeave" }, popup_winid, { current_bufnr })
end

return M
