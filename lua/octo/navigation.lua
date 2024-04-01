local backend = require "octo.backend"
local utils = require "octo.utils"

local M = {}

--[[
Opens a url in your default browser, bypassing gh.

@param url The url to open.
]]
function M.open_in_browser_raw(url)
  local os_name = vim.loop.os_uname().sysname
  local is_windows = vim.loop.os_uname().version:match "Windows"

  if os_name == "Darwin" then
    os.execute("open " .. url)
  elseif os_name == "Linux" then
    os.execute("xdg-open " .. url)
  elseif is_windows then
    os.execute("start " .. url)
  end
end

function M.open_in_browser(kind, repo, number)
  local remote = utils.get_remote_host()
  if not remote then
    utils.error "Cannot find repo remote host"
    return
  end
  local func = backend.get_funcs()["open_in_browser"]
  func(repo, kind, number, remote)
end

local function open_file_if_found(path, line)
  local stat = vim.loop.fs_stat(path)
  if stat and stat.type then
    vim.cmd("e " .. path)
    vim.api.nvim_win_set_cursor(0, { line, 0 })
    return true
  end
  return false
end

function M.go_to_file()
  local bufnr = vim.api.nvim_get_current_buf()
  local path = ""
  local line = vim.api.nvim_win_get_cursor(0)[1]
  if utils.in_diff_window(bufnr) then
    _, path = utils.get_split_and_path(bufnr)
  else
    local buffer = octo_buffers[bufnr]
    if not buffer then
      return
    end
    if not buffer:isPullRequest() then
      return
    end
    local _thread = buffer:get_thread_at_cursor()
    path, line = _thread.path, _thread.line
  end
  local result = open_file_if_found(utils.path_join { vim.fn.getcwd(), path }, line)
  if not result then
    local cmd = "git rev-parse --show-toplevel"
    local git_root = vim.fn.system(cmd):gsub("\n", "")
    result = open_file_if_found(utils.path_join { git_root, path }, line)
  end
  if not result then
    utils.error "Cannot find file in CWD or git path"
  end
end

function M.go_to_issue()
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer then
    return
  end
  local repo, number = utils.extract_issue_at_cursor(buffer.repo)
  if not repo or not number then
    return
  end
  local func = backend.get_funcs()["go_to_issue"]
  func(repo, number)
end

function M.next_comment()
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if buffer.kind then
    local cursor = vim.api.nvim_win_get_cursor(0)
    local current_line = cursor[1]
    local lines = utils.get_sorted_comment_lines(bufnr)
    if not buffer:isReviewThread() then
      -- skil title and body
      lines = utils.tbl_slice(lines, 3, #lines)
    end
    if not lines or not current_line then
      return
    end
    local target
    if current_line < lines[1] + 1 then
      -- go to first comment
      target = lines[1] + 1
    elseif current_line > lines[#lines] + 1 then
      -- do not move
      target = current_line - 1
    else
      for i = #lines, 1, -1 do
        if current_line >= lines[i] + 1 then
          target = lines[i + 1] + 1
          break
        end
      end
    end
    vim.api.nvim_win_set_cursor(0, { target + 1, cursor[2] })
  end
end

function M.prev_comment()
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if buffer.kind then
    local cursor = vim.api.nvim_win_get_cursor(0)
    local current_line = cursor[1]
    local lines = utils.get_sorted_comment_lines(bufnr)
    lines = utils.tbl_slice(lines, 3, #lines)
    if not lines or not current_line then
      return
    end
    local target
    if current_line > lines[#lines] + 2 then
      -- go to last comment
      target = lines[#lines] + 1
    elseif current_line <= lines[1] + 2 then
      -- do not move
      target = current_line - 1
    else
      for i = 1, #lines, 1 do
        if current_line <= lines[i] + 2 then
          target = lines[i - 1] + 1
          break
        end
      end
    end
    vim.api.nvim_win_set_cursor(0, { target + 1, cursor[2] })
  end
end

return M
