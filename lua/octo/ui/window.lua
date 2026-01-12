local utils = require "octo.utils"
local M = {}

---@class octo.BorderHeaderFloatOpts
---@field content? string[]
---@field width integer
---@field border_width integer
---@field padding integer
---@field header string?
---@field header_height integer
---@field height integer
---@field y_offset integer
---@field x_offset integer
---@field enter? boolean

---@param opts octo.BorderHeaderFloatOpts
function M.create_floating_window(opts)
  local winid, bufnr
  bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, opts.content or {})
  local border = "rounded"
  if vim.o.winborder ~= "" and vim.o.winborder ~= "none" then
    border = tostring(vim.o.winborder)
  end
  winid = vim.api.nvim_open_win(bufnr, opts.enter or false, {
    relative = "editor",
    title = opts.header,
    border = border,
    row = opts.y_offset,
    col = opts.x_offset,
    width = opts.width,
    height = opts.height,
    focusable = true,
  })
  vim.bo[bufnr].modifiable = true
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
---@field enter? boolean

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

  -- floating window
  local winid, bufnr = M.create_floating_window {
    content = opts.content,
    width = width,
    border_width = border_width,
    padding = padding,
    header = opts.header,
    header_height = header_height,
    height = height,
    y_offset = y_offset,
    x_offset = x_offset,
    enter = opts.enter,
  }

  -- window binding
  local aucmd = string.format(
    "autocmd BufLeave,BufDelete <buffer=%d> :lua require('octo.ui.window').try_close_wins(%d)",
    bufnr,
    winid
  )
  vim.cmd(aucmd)

  -- mappings
  local mapping_opts = { script = true, silent = true, noremap = true, buffer = bufnr, desc = "Close window" }
  vim.keymap.set("n", "<C-c>", function()
    require("octo.ui.window").try_close_wins(winid)
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
