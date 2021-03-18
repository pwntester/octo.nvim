local format = string.format
local api = vim.api
local strlen = vim.fn.strdisplaywidth

local M = {}

function M.create_border_header_float(opts)
  local outer_winid, outer_bufnr
  outer_bufnr = api.nvim_create_buf(false, true)
  local outer = {}
  local line_fill = string.rep("─", opts.width-2*opts.border_width)
  table.insert(outer, format("┌%s┐", line_fill))
  if opts.header then
    local trimmed_header = string.sub(opts.header, 1, opts.width-2*opts.border_width-2*opts.padding)
    local fill = string.rep(" ", opts.width - 2*opts.padding -2*opts.border_width - strlen(trimmed_header))
    table.insert(outer, format("│ %s%s │", trimmed_header, fill))
    table.insert(outer, format("├%s┤", line_fill))
    for _=1, opts.height-2*opts.border_width-2*opts.header_height do
      table.insert(outer, format("│%s│", string.rep(" ", opts.width-2*opts.border_width)))
    end
  else
    for _=1, opts.height-2*opts.border_width do
      table.insert(outer, format("│%s│", line_fill))
    end
  end
  table.insert(outer, format("└%s┘", line_fill))
  api.nvim_buf_set_lines(outer_bufnr, 0, -1, false, outer)
  outer_winid = api.nvim_open_win(outer_bufnr, false, {
    relative = "editor",
    row = opts.y_offset,
    col = opts.x_offset,
    width = opts.width,
    height = opts.height,
    focusable = false
  })
  api.nvim_buf_set_option(outer_bufnr, "modifiable", false)
  api.nvim_win_set_option(outer_winid, "foldcolumn", "0")
  api.nvim_win_set_option(outer_winid, "signcolumn", "no")
  api.nvim_win_set_option(outer_winid, "number", false)
  api.nvim_win_set_option(outer_winid, "relativenumber", false)
  return outer_winid
end

function M.create_content_float(opts)
  local bufnr = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(bufnr, 0, -1, false, opts.content or {})
  local winid = api.nvim_open_win(bufnr, true, {
    relative = "editor",
    row = opts.header and (opts.y_offset+2*opts.border_width+opts.header_height) or (opts.y_offset+opts.border_width),
    col = opts.x_offset + opts.border_width + opts.padding,
    width = opts.width - 2*opts.border_width - 2*opts.padding,
    height = opts.header and (opts.height-3*opts.border_width-2*opts.header_height) or (opts.height-2*opts.border_width),
    focusable = true
  })
  api.nvim_win_set_option(winid, "previewwindow", true)
  api.nvim_win_set_option(winid, "foldcolumn", "0")
  api.nvim_win_set_option(winid, "signcolumn", "no")
  api.nvim_win_set_option(winid, "number", false)
  api.nvim_win_set_option(winid, "relativenumber", false)
  return winid, bufnr
end

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
      max_line = math.max(strlen(line), max_line)
    end
  end
  -- calculate window height/width
  opts.border_width = 1
  opts.padding = 1
  opts.header_height = 1
  if max_line > 0 then
    -- pre-defined content
    opts.width = math.min(vim_width * 0.9, max_line + 2*opts.padding + 2*opts.border_width)
    if opts.header then
      opts.height = math.min(vim_height, 3*opts.border_width + opts.header_height + strlen(opts.content))
    else
      opts.height = math.min(vim_height, 2*opts.border_width + strlen(opts.content))
    end
  else
    opts.width = math.floor(vim_width * opts.x_percent)
    opts.height = math.floor(vim_height * opts.y_percent)
  end
  -- calculate offsets
  opts.x_offset = math.floor((vim_width - opts.width) / 2)
  opts.y_offset = math.floor((vim_height - opts.height) / 2)

  -- outer win (header + border)
  local outer_winid = M.create_border_header_float(opts)

  -- content win
  local winid, bufnr = M.create_content_float(opts)

  -- window binding
  local aucmd = string.format(
    "autocmd BufLeave,BufDelete <buffer=%d> :lua require('octo.window').try_close_wins(%d, %d)",
    bufnr,
    winid,
    outer_winid)
  vim.cmd(aucmd)

  -- mappings
  local mapping_opts = {script = true, silent = true, noremap = true}
  api.nvim_buf_set_keymap(bufnr, "n", "<C-c>", format("<cmd>lua require'octo.window'.try_close_wins(%d, %d)<CR>", winid, outer_winid), mapping_opts)

  return winid, bufnr
end

function M.try_close_wins(...)
  for _, win_id in ipairs({...}) do
    pcall(vim.api.nvim_win_close, win_id, true)
  end
end

function M.create_comment_popup(win, comment)
  local vertical_offset = vim.fn.line(".") - vim.fn.line("w0")
  local win_width = vim.fn.winwidth(win)
  local horizontal_offset = math.floor(win_width / 4) -- 1/4 of win width
  local header = {format(" %s %s[%s] [%s]", comment.author.login, comment.viewerDidAuthor and "[Author] " or " ", comment.authorAssociation, comment.state)}
  local border_width = 1
  local padding = 1
  local body = vim.list_extend(header, vim.split(comment.body, "\n"))
  local height = math.min(2*border_width + strlen(body), vim.fn.winheight(win))

  local preview_bufnr = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(preview_bufnr, 0, -1, false, body)
  local preview_width = win_width - 2*border_width - 2*padding - horizontal_offset
  local preview_col = comment.diffSide == "LEFT" and (padding + border_width) or (padding + border_width + horizontal_offset)
  local preview_winid = api.nvim_open_win(preview_bufnr, false, {
    relative = "win",
    win = win,
    row = vertical_offset + padding,
    col = preview_col,
    width = preview_width,
    height = height - 2*border_width
  })
  api.nvim_win_set_option(preview_winid, "foldcolumn", "0")
  api.nvim_win_set_option(preview_winid, "signcolumn", "no")
  api.nvim_win_set_option(preview_winid, "number", false)
  api.nvim_win_set_option(preview_winid, "relativenumber", false)
  vim.lsp.util.close_preview_autocmd({"CursorMoved", "CursorMovedI", "WinLeave"}, preview_winid)

  local border = {}
  local borderwin_width = win_width - horizontal_offset
  local line_fill = string.rep("─", borderwin_width-2*border_width)
  local border_col = comment.diffSide == "LEFT" and 0 or horizontal_offset
  table.insert(border, format("┌%s┐", line_fill))
  for _=1, height-2 do
    table.insert(border, format("│%s│", string.rep(" ", borderwin_width-2*border_width)))
  end
  table.insert(border, format("└%s┘", line_fill))
  local border_bufnr = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(border_bufnr, 0, -1, false, border)
  local border_winid = api.nvim_open_win(border_bufnr, false, {
    relative = "win",
    win = win,
    row = vertical_offset,
    col = border_col,
    width = borderwin_width,
    height = height
  })
  api.nvim_win_set_option(border_winid, "foldcolumn", "0")
  api.nvim_win_set_option(border_winid, "signcolumn", "no")
  api.nvim_win_set_option(border_winid, "number", false)
  api.nvim_win_set_option(border_winid, "relativenumber", false)
  vim.lsp.util.close_preview_autocmd({"CursorMoved", "CursorMovedI", "WinLeave"}, border_winid)
end

function M.create_popup(opts)
  opts = opts or {}
  if not opts.width then
    opts.width = 30
  end
  if not opts.height then
    opts.height = 10
  end

  local border_width = 1
  local popup_winid = api.nvim_open_win(opts.bufnr, false, {
    relative = "cursor",
    anchor = "SW",
    row = -2,
    col = 2,
    focusable = false,
    style = "minimal",
    width = opts.width-2*border_width,
    height = opts.height-2*border_width
  })
  vim.lsp.util.close_preview_autocmd({"CursorMoved", "CursorMovedI", "WinLeave"}, popup_winid)

  local border = {}
  table.insert(border, format("┌%s┐", string.rep("─", opts.width-2*border_width)))
  for _=1, opts.height-2 do
    table.insert(border, format("│%s│", string.rep(" ", opts.width-2*border_width)))
  end
  table.insert(border, format("└%s┘", string.rep("─", opts.width-2*border_width)))
  local border_bufnr = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(border_bufnr, 0, -1, false, border)
  local border_winid = api.nvim_open_win(border_bufnr, false, {
    relative = "cursor",
    anchor = "SW",
    row = -1,
    col = 1,
    focusable = false,
    style = "minimal",
    width = opts.width,
    height = opts.height
  })
  api.nvim_win_set_option(border_winid, "foldcolumn", "0")
  api.nvim_win_set_option(border_winid, "signcolumn", "no")
  api.nvim_win_set_option(border_winid, "number", false)
  api.nvim_win_set_option(border_winid, "relativenumber", false)
  vim.lsp.util.close_preview_autocmd({"CursorMoved", "CursorMovedI", "WinLeave"}, border_winid)
end

return M
