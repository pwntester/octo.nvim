local popup = require "popup"
local format = string.format
local api = vim.api

local M = {}

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
      max_line = math.max(#line, max_line)
    end
  end

  -- calculate window height/width
  local width, height
  if max_line > 0 then
    -- pre-defined content
    width = math.min(vim_width * 0.9, max_line)
    if opts.header then
      height = math.min(vim_height, 2 + #opts.content)
    else
      height = math.min(vim_height, #opts.content)
    end
  else
    width = math.floor(vim_width * opts.x_percent)
    height = math.floor(vim_height * opts.y_percent)
  end

  -- calculate offsets
  local x_offset = (vim_width - width) / 2
  local y_offset = (vim_height - height) / 2
  local header_winid
  local header_win_opts = {border = {}}
  if opts.header then
    header_winid, header_win_opts =
      popup.create(
      {opts.header},
      {
        moved = "non-existant",
        line =y_offset,
        col = x_offset,
        minwidth = width,
        maxheight = 2,
        border = {1, 1, 0, 1},
        borderchars = {"─", "│", "", "│", "┌", "┐", "┤", "├"},
        padding = {0, 0, 0, 0}
      }
    )
    api.nvim_buf_call(header_win_opts.border.bufnr, function()
      vim.cmd("setlocal eventignore+=WinClosed,WinLeave")
    end)
    local header_bufnr = api.nvim_win_get_buf(header_winid)
    api.nvim_buf_set_option(header_bufnr, "modifiable", false)
  end
  local winid =
    popup.create(
    opts.content or {},
    {
      moved = "non-existant",
      line = opts.header and y_offset+2 or y_offset,
      col = x_offset,
      minwidth = width,
      minheight = height,
      border = {1, 1, 1, 1},
      borderchars = opts.header and {"─", "│", "─", "│", "├", "┤", "┘", "└"} or {"─", "│", "─", "│", "┌", "┐", "┘", "└"},
      padding = {0, 0, 0, 0}
    }
  )
  local bufnr = api.nvim_win_get_buf(winid)
  if header_winid then
    vim.cmd(string.format(
      "autocmd BufLeave,BufDelete <buffer=%d> ++nested ++once :lua require('octo.window').try_close_wins(%d, %d, %d)",
      bufnr,
      winid,
      header_winid,
      header_win_opts.border.win_id))
  else
    vim.cmd(string.format(
      "autocmd BufLeave,BufDelete <buffer=%d> ++nested ++once :lua require('octo.window').try_close_wins(%d)",
      bufnr,
      winid))
  end
  local mapping_opts = {script = true, silent = true, noremap = true}
  api.nvim_buf_set_keymap(bufnr, "n", "<C-c>", format("<cmd>lua require'octo.window'.try_close_wins(%d)<CR>", winid), mapping_opts)

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
  local horizontal_offset = math.floor(win_width / 4)
  local header = {format(" %s %s[%s] [%s]", comment.author.login, comment.viewerDidAuthor and "[Author] " or " ", comment.authorAssociation, comment.state)}
  local body = vim.list_extend(header, vim.split(comment.body, "\n"))
  local height = math.min(2 + #body, vim.fn.winheight(win))
  local padding = 1

  local preview_bufnr = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(preview_bufnr, 0, -1, false, body)
  local preview_width = win_width - 2 - (padding * 2) - horizontal_offset
  local preview_col = comment.diffSide == "LEFT" and (padding + 1) or (padding + 1 + horizontal_offset)
  local preview_winid = api.nvim_open_win(preview_bufnr, false, {
    relative = "win",
    win = win,
    row = vertical_offset + 1,
    col = preview_col,
    width = preview_width,
    height = height - 2
  })
  api.nvim_win_set_option(preview_winid, "foldcolumn", "0")
  api.nvim_win_set_option(preview_winid, "signcolumn", "no")
  api.nvim_win_set_option(preview_winid, "number", false)
  api.nvim_win_set_option(preview_winid, "relativenumber", false)
  vim.lsp.util.close_preview_autocmd({"CursorMoved", "CursorMovedI", "WinLeave"}, preview_winid)

  local border = {}
  local border_width = win_width - horizontal_offset
  local border_col = comment.diffSide == "LEFT" and 0 or horizontal_offset
  table.insert(border, format("┌%s┐", string.rep("─", border_width-2)))
  for _=1, height-2 do
    table.insert(border, format("│%s│", string.rep(" ", border_width-2)))
  end
  table.insert(border, format("└%s┘", string.rep("─", border_width-2)))
  local border_bufnr = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(border_bufnr, 0, -1, false, border)
  local border_winid = api.nvim_open_win(border_bufnr, false, {
    relative = "win",
    win = win,
    row = vertical_offset,
    col = border_col,
    width = border_width,
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

  local popup_bufnr = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(popup_bufnr, 0, -1, false, opts.content)
  local popup_winid = api.nvim_open_win(popup_bufnr, false, {
    relative = "cursor",
    anchor = "NW",
    row = 2,
    col = 2,
    focusable = false,
    style = "minimal",
    width = opts.width-2,
    height = opts.height-2
  })
  vim.lsp.util.close_preview_autocmd({"CursorMoved", "CursorMovedI", "WinLeave"}, popup_winid)

  local border = {}
  table.insert(border, format("┌%s┐", string.rep("─", opts.width-2)))
  for _=1, opts.height-2 do
    table.insert(border, format("│%s│", string.rep(" ", opts.width-2)))
  end
  table.insert(border, format("└%s┘", string.rep("─", opts.width-2)))
  local border_bufnr = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(border_bufnr, 0, -1, false, border)
  local border_winid = api.nvim_open_win(border_bufnr, false, {
    relative = "cursor",
    anchor = "NW",
    row = 1,
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

M.create_popup({
  content = {"foo", "bar"},
  width = 40,
  height = 10
})

return M
