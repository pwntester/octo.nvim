-- Heavily derived from `diffview.nvim`:
-- https://github.com/sindrets/diffview.nvim/blob/main/lua/diffview/file-entry.lua
--
local utils = require'octo.util'
local config = require'octo.config'
local signs = require'octo.signs'
local mappings = require'octo.mappings'
local M = {}

---@type integer|nil
M._null_buffer = nil

---@class GitStats
---@field additions integer
---@field deletions integer
---@field changes integer

---@class FileEntry
---@field path string
---@field basename string
---@field extension string
---@field pull_request PullRequest
---@field status string
---@field patch string
---@field stats GitStats
---@field left_binary boolean|nil
---@field right_binary boolean|nil
---@field left_bufid integer
---@field right_bufid integer
---@field left_bufname string
---@field right_bufname string
---@field left_lines string[]
---@field right_lines string[]
---@field left_comment_ranges table
---@field right_comment_ranges table
---@field associated_bufs integer[]
---@field diffhunks string[]
local FileEntry = {}
FileEntry.__index = FileEntry

FileEntry.winopts = {
  foldmethod = "diff",
  foldlevel = 0
}

---FileEntry constructor
---@param opt table
---@return FileEntry
function FileEntry:new(opt)
  local pr = opt.pull_request
  local diffhunks, left_ranges, right_ranges = utils.process_patch(opt.patch)
  local current_review = require"octo.reviews".get_current_review()
  local left_bufname = string.format("octo://%s/review/%s/file/LEFT/%s", pr.repo, current_review.id, opt.path)
  local right_bufname = string.format("octo://%s/review/%s/file/RIGHT/%s", pr.repo, current_review.id, opt.path)

  local this = {
    path = opt.path,
    patch = opt.patch,
    basename = utils.path_basename(opt.path),
    extension = utils.path_extension(opt.path),
    pull_request = pr,
    status = opt.status,
    stats = opt.stats,
    left_bufname = left_bufname,
    right_bufname = right_bufname,
    left_comment_ranges = left_ranges,
    right_comment_ranges = right_ranges,
    diffhunks = diffhunks,
    associated_bufs = {}
  }

  setmetatable(this, self)

  return this
end

---FileEntry finalizer
function FileEntry:destroy()
  self:detach_buffers()
  for _, bn in ipairs(self.associated_bufs) do
    if bn ~= M._null_buffer then
      pcall(vim.api.nvim_buf_delete, bn, {force = true})
    end
  end
end

---Get the window id for the alternative side of the provided buffer
---@param split string
---@return integer
function FileEntry:get_alternative_win(split)
  if split:lower() == "left" then
    return self.right_winid
  elseif split:lower() == "right" then
    return self.left_winid
  end
end

---Get the buffer id for the alternative side of the provided buffer
---@param split string
---@return integer
function FileEntry:get_alternative_buf(split)
  if split:lower() == "left" then
    return self.right_bufid
  elseif split:lower() == "right" then
    return self.left_bufid
  end
end

---Get the window id for the side of the provided buffer
---@param split string
---@return integer
function FileEntry:get_win(split)
  if split:lower() == "left" then
    return self.left_winid
  elseif split:lower() == "right" then
    return self.right_winid
  end
end

---Get the buffer id for the side of the provided buffer
---@param split string
---@return integer
function FileEntry:get_buf(split)
  if split:lower() == "left" then
    return self.left_bufid
  elseif split:lower() == "right" then
    return self.right_bufid
  end
end

---Fetch file content from GitHub.
function FileEntry:fetch()
  utils.get_file_contents(self.pull_request.repo, self.pull_request.right:abbrev(), self.path, function(lines)
    self.right_lines = lines
  end)
  utils.get_file_contents(self.pull_request.repo, self.pull_request.left:abbrev(), self.path, function(lines)
    self.left_lines = lines
  end)
end

---Load the buffers.
---@param left_winid integer
---@param right_winid integer
function FileEntry:load_buffers(left_winid, right_winid)
  local splits = {
    {
      winid = left_winid, bufid = self.left_bufid,
      bufname = self.left_bufname, pos = "left", binary = self.left_binary == true
    },
    {
      winid = right_winid, bufid = self.right_bufid,
      bufname = self.right_bufname, pos = "right", binary = self.right_binary == true
    }
  }

  for _, split in ipairs(splits) do
    if not split.bufid or not vim.api.nvim_buf_is_loaded(split.bufid) then
      local bn = M._create_buffer(split.bufname, split.binary)
      table.insert(self.associated_bufs, bn)
      vim.api.nvim_win_set_buf(split.winid, bn)
      split.bufid = bn
      M._attach_buffer(split.bufid)
    else
      vim.api.nvim_win_set_buf(split.winid, split.bufid)
      M._attach_buffer(split.bufid)
    end
  end
  self.left_bufid = splits[1].bufid
  self.right_bufid = splits[2].bufid
  self.left_winid = splits[1].winid
  self.right_winid = splits[2].winid

  if self.left_lines and self.right_lines then
    M._write_buffer(self.right_bufid, self.right_lines)
    M._write_buffer(self.left_bufid, self.left_lines)
    self:place_signs()
  end

  M._update_windows(left_winid, right_winid)
end

function FileEntry:attach_buffers()
  if self.left_bufid then M._attach_buffer(self.left_bufid) end
  if self.right_bufid then M._attach_buffer(self.right_bufid) end
end

function FileEntry:detach_buffers()
  if self.left_bufid then M._detach_buffer(self.left_bufid) end
  if self.right_bufid then M._detach_buffer(self.right_bufid) end
end

---Compare against another FileEntry.
---@param other FileEntry
---@return boolean
function FileEntry:compare(other)
  if self.stats and not other.stats then return false end
  if not self.stats and other.stats then return false end
  if self.stats and other.stats then
    if (self.stats.additions ~= other.stats.additions
        or self.stats.deletions ~= other.stats.deletions) then
      return false
    end
  end

  return (
    self.path == other.path
    and self.status == other.status
    )
end

---Update thread signs in diff buffers.
function FileEntry:place_signs()
  local splits = {
    {bufnr = self.left_bufid, comment_ranges = self.left_comment_ranges},
    {bufnr = self.right_bufid, comment_ranges = self.right_comment_ranges},
  }
  for _, split in ipairs(splits) do
    signs.unplace(split.bufnr)

    for _, range in ipairs(split.comment_ranges) do
      for line = range[1], range[2] do
        signs.place("octo_comment_range", split.bufnr, line - 1)
      end
    end

    local threads = vim.tbl_values(require"octo.reviews".get_current_review().threads)
    for _, thread in ipairs(threads) do
      if utils.is_thread_placed_in_buffer(thread, split.bufnr) then
        local line = thread.startLine
        --for line = thread.startLine, thread.line do
          local sign = "octo_thread"

          if thread.isOutdated then
            sign = sign .. "_outdated"
          elseif thread.isResolved then
            sign = sign .. "_resolved"
          end

          for _, comment in ipairs(thread.comments.nodes) do
            if comment.state == "PENDING" then
              sign = sign .. "_pending"
              break
            end
          end

          signs.place(sign, split.bufnr, line - 1)
        --end
      end
    end
  end
end

---Get the bufid of the null buffer. Create it if it's not loaded.
---@return integer
function M._get_null_buffer()
  if not (M._null_buffer and vim.api.nvim_buf_is_loaded(M._null_buffer)) then
    local bn = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_buf_set_lines(bn, 0, -1, false, {"Loading ..."})
    local bufname = utils.path_join({"octo", "null"})
    vim.api.nvim_buf_set_option(bn, "modified", false)
    vim.api.nvim_buf_set_option(bn, "modifiable", false)

    local ok = pcall(vim.api.nvim_buf_set_name, bn, bufname)
    if not ok then
      utils.wipe_named_buffer(bufname)
      vim.api.nvim_buf_set_name(bn, bufname)
    end

    M._null_buffer = bn
  end

  return M._null_buffer
end

function M._create_buffer(bufname, null)
  if null then return M._get_null_buffer() end

  local bn = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_buf_set_name(bn, bufname)
  vim.api.nvim_buf_set_option(bn, "modified", false)
  vim.api.nvim_buf_set_option(bn, "modifiable", false)
  return bn
end

function M._write_buffer(bufid, lines)
  vim.api.nvim_buf_set_option(bufid, "modifiable", true)
  vim.api.nvim_buf_set_lines(bufid, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(bufid, "modifiable", false)
  vim.api.nvim_buf_call(bufid, function()
    vim.cmd [[filetype detect]]
    vim.cmd [[doau BufEnter]]
    vim.cmd [[diffthis]]
    --vim.cmd [[normal! gg]c]]
  end)
end

function M.load_null_buffer(winid)
  local bn = M._get_null_buffer()
  vim.api.nvim_win_set_buf(winid, bn)
  M._attach_buffer(bn)
end

function M._update_windows(left_winid, right_winid)
  for _, id in ipairs({ left_winid, right_winid }) do
    for k, v in pairs(FileEntry.winopts) do
      vim.api.nvim_win_set_option(id, k, v)
    end
  end

  -- Scroll to trigger the scrollbind and sync the windows. This works more
  -- consistently than calling `:syncbind`.
  vim.cmd([[exec "normal! \<c-y>"]])
end

function M._attach_buffer(bufid)
  local conf = config.get_config()
  for rhs, lhs in pairs(conf.mappings.review_diff) do
    vim.api.nvim_buf_set_keymap(bufid, "n", lhs, mappings.callback(rhs), { noremap = true, silent = true })
  end
  vim.cmd(string.format("nnoremap %s :OctoAddReviewComment<CR>", conf.mappings.review_thread.add_comment))
  vim.cmd(string.format("vnoremap %s :OctoAddReviewComment<CR>", conf.mappings.review_thread.add_comment))
  vim.cmd(string.format("nnoremap %s :OctoAddReviewSuggestion<CR>", conf.mappings.review_thread.add_suggestion))
  vim.cmd(string.format("vnoremap %s :OctoAddReviewSuggestion<CR>", conf.mappings.review_thread.add_suggestion))
end

function M._detach_buffer(bufid)
  local conf = config.get_config()
  for _, lhs in pairs(conf.mappings.review_diff) do
    pcall(vim.api.nvim_buf_del_keymap, bufid, "n", lhs)
  end
end

M.FileEntry = FileEntry

return M

