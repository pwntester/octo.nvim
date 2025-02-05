local OctoBuffer = require("octo.model.octo-buffer").OctoBuffer
local utils = require "octo.utils"
local vim = vim

local M = {}

---Show review threads under cursor if there are any
---@param jump_to_buffer boolean
function M.show_review_threads(jump_to_buffer)
  -- This function is called from a very broad CursorHold event
  -- Check if we are in a diff buffer and otherwise return early
  local bufnr = vim.api.nvim_get_current_buf()
  local split, path = utils.get_split_and_path(bufnr)
  if not split or not path then
    -- not on a diff buffer
    return
  end

  local review = require("octo.reviews").get_current_review()
  if not review then
    -- cant find an active review
    return
  end

  local file = review.layout:get_current_file()
  if not file then
    -- cant find the changed file metadata
    return
  end

  local pr = file.pull_request
  local review_level = review:get_level()
  local threads = vim.tbl_values(review.threads)
  local line = vim.api.nvim_win_get_cursor(0)[1]

  -- get threads associated with current line
  local threads_at_cursor = {}
  for _, thread in ipairs(threads) do
    if
      review_level == "PR"
      and utils.is_thread_placed_in_buffer(thread, bufnr)
      and thread.startLine <= line
      and thread.line >= line
    then
      table.insert(threads_at_cursor, thread)
    elseif review_level == "COMMIT" then
      local commit
      if split == "LEFT" then
        commit = review.layout.left.commit
      else
        commit = review.layout.right.commit
      end
      for _, comment in ipairs(thread.comments.nodes) do
        if commit == comment.originalCommit.oid and thread.originalLine == line then
          table.insert(threads_at_cursor, thread)
          break
        end
      end
    end
  end

  -- render thread buffer if there are threads at the current line
  if #threads_at_cursor > 0 then
    review.layout:ensure_layout()
    local alt_win = file:get_alternative_win(split)
    if vim.api.nvim_win_is_valid(alt_win) then
      local thread_buffer = M.create_thread_buffer(threads_at_cursor, pr.repo, pr.number, split, file.path)
      if thread_buffer then
        table.insert(file.associated_bufs, thread_buffer.bufnr)
        vim.api.nvim_win_set_buf(alt_win, thread_buffer.bufnr)
        thread_buffer:configure()

        vim.keymap.set("n", "q", function()
          M.hide_thread_buffer(split, file)
          local file_win = file:get_win(split)
          if vim.api.nvim_win_is_valid(file_win) then
            vim.api.nvim_set_current_win(file_win)
          end
        end, { buffer = thread_buffer.bufnr })

        if jump_to_buffer then
          vim.api.nvim_set_current_win(alt_win)
        end
        vim.api.nvim_buf_call(thread_buffer.bufnr, function()
          vim.cmd [[diffoff!]]
          pcall(vim.cmd.normal, "]c")
        end)
      end
    end
  else
    -- no threads at the current line, hide the thread buffer
    M.hide_thread_buffer(split, file)
  end
end

function M.hide_thread_buffer(split, file)
  local alt_buf = file:get_alternative_buf(split)
  local alt_win = file:get_alternative_win(split)
  if vim.api.nvim_win_is_valid(alt_win) and vim.api.nvim_buf_is_valid(alt_buf) then
    local current_alt_bufnr = vim.api.nvim_win_get_buf(alt_win)
    if current_alt_bufnr ~= alt_buf then
      -- if we are not showing the corresponging alternative diff buffer, do so
      vim.api.nvim_win_set_buf(alt_win, alt_buf)

      -- show the diff
      file:show_diff()
    end
  end
end

---Create a thread buffer
---@param threads ReviewThread[]
---@param repo any
---@param number any
---@param side any
---@param path any
---@return OctoBuffer | nil
function M.create_thread_buffer(threads, repo, number, side, path)
  local current_review = require("octo.reviews").get_current_review()
  if not current_review then
    return
  end

  if not vim.startswith(path, "/") then
    path = "/" .. path
  end
  local line = threads[1].originalStartLine ~= vim.NIL and threads[1].originalStartLine or threads[1].originalLine
  local bufname = string.format("octo://%s/review/%s/threads/%s%s:%d", repo, current_review.id, side, path, line)
  local existing_bufnr = vim.fn.bufnr(bufname)

  if existing_bufnr ~= -1 then
    if vim.api.nvim_buf_is_loaded(existing_bufnr) then
      return octo_buffers[existing_bufnr]
    end

    -- Weird situation, force delete buffer and start from scratch
    vim.api.nvim_buf_delete(existing_bufnr, { force = true })
  end

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(bufnr, bufname)
  local buffer = OctoBuffer:new {
    bufnr = bufnr,
    number = number,
    repo = repo,
  }
  buffer:render_threads(threads)
  buffer:render_signs()
  return buffer
end

return M
