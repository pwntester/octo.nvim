local constants = require "octo.constants"
local graphql = require "octo.graphql"
local utils = require "octo.utils"
local gh = require "octo.gh"

local M = {}

function M.open_in_browser(kind, repo, number)
  local cmd
  if not kind and not repo then
    local bufnr = vim.api.nvim_get_current_buf()
    local buffer = octo_buffers[bufnr]
    if not buffer then
      return
    end
    if buffer:isPullRequest() then
      cmd = string.format("gh pr view --web -R %s %d", buffer.repo, buffer.number)
    elseif buffer:isIssue() then
      cmd = string.format("gh issue view --web -R %s %d", buffer.repo, buffer.number)
    elseif buffer:isRepo() then
      cmd = string.format("gh repo view --web %s", buffer.repo)
    end
  else
    if kind == "pr" or kind == "pull_request" then
      cmd = string.format("gh pr view --web -R %s %d", repo, number)
    elseif kind == "issue" then
      cmd = string.format("gh issue view --web -R %s %d", repo, number)
    elseif kind == "repo" then
      cmd = string.format("gh repo view --web %s", repo)
    end
  end
  pcall(vim.cmd, "silent !" .. cmd)
end

function M.go_to_file()
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer then
    return
  end
  if not buffer:isPullRequest() then
    return
  end
  local _thread = utils.get_thread_at_cursor(bufnr)
  local stat = vim.loop.fs_stat(utils.path_join { vim.fn.getcwd(), _thread.path })
  if stat and stat.type then
    vim.cmd("e " .. _thread.path)
    vim.api.nvim_win_set_cursor(0, { _thread.line, 0 })
  else
    utils.notify("[Octo] Cannot find file in CWD", 2)
  end
end

function M.go_to_issue()
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer then
    return
  end
  local current_repo = buffer.repo

  local repo, number = utils.extract_pattern_at_cursor(constants.LONG_ISSUE_PATTERN)

  if not repo or not number then
    repo = current_repo
    number = utils.extract_pattern_at_cursor(constants.SHORT_ISSUE_PATTERN)
  end

  if not repo or not number then
    repo, _, number = utils.extract_pattern_at_cursor(constants.URL_ISSUE_PATTERN)
  end

  if repo and number then
    local owner, name = utils.split_repo(repo)
    local query = graphql("issue_kind_query", owner, name, number)
    gh.run {
      args = { "api", "graphql", "-f", string.format("query=%s", query) },
      cb = function(output, stderr)
        if stderr and not utils.is_blank(stderr) then
          vim.api.nvim_err_writeln(stderr)
        elseif output then
          local resp = vim.fn.json_decode(output)
          local kind = resp.data.repository.issueOrPullRequest.__typename
          if kind == "Issue" then
            utils.get_issue(repo, number)
          elseif kind == "PullRequest" then
            utils.get_pull_request(repo, number)
          end
        end
      end,
    }
  end
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
