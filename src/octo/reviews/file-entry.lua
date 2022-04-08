-- Heavily derived from `diffview.nvim`:
-- https://github.com/sindrets/diffview.nvim/blob/main/lua/diffview/file-entry.lua
--
local utils = require "octo.utils"
local graphql = require "octo.graphql"
local gh = require "octo.gh"
local config = require "octo.config"
local signs = require "octo.signs"
local mappings = require "octo.mappings"
local M = {}

---@type table
M._null_buffer = {}

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
---@field left_lines string[]
---@field right_lines string[]
---@field left_comment_ranges table
---@field right_comment_ranges table
---@field associated_bufs integer[]
---@field diffhunks string[]
---@field viewed_state string
local FileEntry = {}
FileEntry.__index = FileEntry

FileEntry.winopts = {
  foldmethod = "diff",
  foldlevel = 0,
}

---FileEntry constructor
---@param opt table
---@return FileEntry
function FileEntry:new(opt)
  local pr = opt.pull_request
  local diffhunks, left_ranges, right_ranges
  if opt.patch then
    diffhunks, left_ranges, right_ranges = utils.process_patch(opt.patch)
  end

  local this = {
    path = opt.path,
    previous_path = opt.previous_path,
    patch = opt.patch,
    basename = utils.path_basename(opt.path),
    extension = utils.path_extension(opt.path),
    pull_request = pr,
    status = opt.status,
    stats = opt.stats,
    left_comment_ranges = left_ranges,
    right_comment_ranges = right_ranges,
    left_binary = opt.left_binary,
    right_binary = opt.right_binary,
    diffhunks = diffhunks,
    associated_bufs = {},
    viewed_state = pr.files[opt.path],
  }
  if not this.status then
    this.status = " "
  end

  setmetatable(this, self)

  return this
end

---FileEntry toggle_viewed
function FileEntry:toggle_viewed()
  local query, next_state
  if self.viewed_state == "VIEWED" then
    query = graphql("unmark_file_as_viewed_mutation", self.path, self.pull_request.id)
    next_state = "UNVIEWED"
  elseif self.viewed_state == "UNVIEWED" then
    query = graphql("mark_file_as_viewed_mutation", self.path, self.pull_request.id)
    next_state = "VIEWED"
  elseif self.viewed_state == "DISMISSED" then
    query = graphql("mark_file_as_viewed_mutation", self.path, self.pull_request.id)
    next_state = "VIEWED"
  end
  gh.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        vim.api.nvim_err_writeln(stderr)
      elseif output then
        --local resp = vim.fn.json_decode(output)
        self.viewed_state = next_state
        local current_review = require("octo.reviews").get_current_review()
        if current_review then
          current_review.layout.file_panel:render()
          current_review.layout.file_panel:redraw()
        end
      end
    end,
  }
end

---FileEntry finalizer
function FileEntry:destroy()
  self:detach_buffers()
  for _, bn in ipairs(self.associated_bufs) do
    pcall(vim.api.nvim_buf_delete, bn, { force = true })
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

---Fetch file content locally or from GitHub.
function FileEntry:fetch()
  local right_path = self.path
  local left_path = self.path

  -- handle renamed files
  if self.status == "R" and self.previous_path then
    left_path = self.previous_path
  end

  -- fetch right version
  if self.pull_request.local_right then
    utils.get_file_at_commit(right_path, self.pull_request.right.commit, function(lines)
      self.right_lines = lines
    end)
  else
    utils.get_file_contents(self.pull_request.repo, self.pull_request.right:abbrev(), right_path, function(lines)
      self.right_lines = lines
    end)
  end

  -- fetch left version
  if self.pull_request.local_left then
    utils.get_file_at_commit(left_path, self.pull_request.left.commit, function(lines)
      self.left_lines = lines
    end)
  else
    utils.get_file_contents(self.pull_request.repo, self.pull_request.left:abbrev(), left_path, function(lines)
      self.left_lines = lines
    end)
  end

  -- wait until we have both versions
  return vim.wait(5000, function()
    return self.left_lines and self.right_lines
  end)
end

---Load the buffers.
---@param left_winid integer
---@param right_winid integer
function FileEntry:load_buffers(left_winid, right_winid)
  local empty_files = #self.left_lines == 0 and #self.right_lines == 0
  local splits = {
    {
      winid = left_winid,
      bufid = self.left_bufid,
      lines = self.left_lines,
      pos = "left",
      binary = self.left_binary == true or empty_files,
    },
    {
      winid = right_winid,
      bufid = self.right_bufid,
      lines = self.right_lines,
      pos = "right",
      binary = self.right_binary == true or empty_files,
    },
  }

  -- configure diff buffers
  for _, split in ipairs(splits) do
    if not split.bufid or not vim.api.nvim_buf_is_loaded(split.bufid) then
      local use_local = false
      if split.pos == "right" and utils.in_pr_branch(self.pull_request.bufnr) then
        use_local = true
      end

      -- create buffer
      split.bufid = M._create_buffer {
        status = self.status,
        show_diff = self.patch ~= nil,
        path = self.path,
        split = split.pos,
        binary = split.binary,
        lines = split.lines,
        repo = self.pull_request.repo,
        use_local = use_local,
      }

      -- register new buffer
      table.insert(self.associated_bufs, split.bufid)
      self[split.pos .. "_bufid"] = split.bufid
      self[split.pos .. "_winid"] = split.winid
    end

    M._configure_buffer(split.bufid)
    vim.api.nvim_win_set_buf(split.winid, split.bufid)
  end

  -- show thread signs and virtual text
  self:place_signs()

  -- configure windows
  M._configure_windows(left_winid, right_winid)

  -- activate diff
  for _, split in ipairs(splits) do
    vim.api.nvim_buf_call(split.bufid, function()
      vim.cmd [[filetype detect]]
      vim.cmd [[doau BufEnter]]
      vim.cmd [[diffthis]]
      -- Scroll to trigger the scrollbind and sync the windows. This works more
      -- consistently than calling `:syncbind`.
      vim.cmd [[exec "normal! \<c-y>"]]
    end)
  end
end

function FileEntry:attach_buffers()
  if self.left_bufid then
    M._configure_buffer(self.left_bufid)
  end
  if self.right_bufid then
    M._configure_buffer(self.right_bufid)
  end
end

function FileEntry:detach_buffers()
  if self.left_bufid then
    M._detach_buffer(self.left_bufid)
  end
  if self.right_bufid then
    M._detach_buffer(self.right_bufid)
  end
end

---Compare against another FileEntry.
---@param other FileEntry
---@return boolean
function FileEntry:compare(other)
  if self.stats and not other.stats then
    return false
  end
  if not self.stats and other.stats then
    return false
  end
  if self.stats and other.stats then
    if self.stats.additions ~= other.stats.additions or self.stats.deletions ~= other.stats.deletions then
      return false
    end
  end

  return (self.path == other.path and self.status == other.status)
end

---Update thread signs in diff buffers.
function FileEntry:place_signs()
  local splits = {
    { bufnr = self.left_bufid, comment_ranges = self.left_comment_ranges },
    { bufnr = self.right_bufid, comment_ranges = self.right_comment_ranges },
  }
  for _, split in ipairs(splits) do
    signs.unplace(split.bufnr)

    -- place comment range signs
    if split.comment_ranges then
      for _, range in ipairs(split.comment_ranges) do
        for line = range[1], range[2] do
          signs.place("octo_comment_range", split.bufnr, line - 1)
        end
      end
    end

    -- place thread comments signs and virtual text
    local threads = vim.tbl_values(require("octo.reviews").get_current_review().threads)
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

        local last_comment = thread.comments.nodes[#thread.comments.nodes]
        local last_date = last_comment.lastEditedAt ~= vim.NIL and last_comment.lastEditedAt or last_comment.createdAt
        local vt_msg = string.format("%d comments (%s)", #thread.comments.nodes, utils.format_date(last_date))
        vim.api.nvim_buf_set_virtual_text(split.bufnr, -1, line - 1, { { vt_msg, "Comment" } }, {})
        --end
      end
    end
  end
end

function M._create_buffer(opts)
  local current_review = require("octo.reviews").get_current_review()
  local bufnr
  if opts.use_local then
    bufnr = vim.fn.bufadd(opts.path)
  else
    bufnr = vim.api.nvim_create_buf(false, false)
    local bufname = string.format(
      "octo://%s/review/%s/file/%s/%s",
      opts.repo,
      current_review.id,
      string.upper(opts.split),
      opts.path
    )
    vim.api.nvim_buf_set_name(bufnr, bufname)
    if opts.binary then
      vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "Binary file" })
    elseif opts.status == "R" and not opts.show_diff then
      vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "Renamed" })
    elseif opts.lines then
      vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, opts.lines)
    end
  end
  vim.api.nvim_buf_set_option(bufnr, "modified", false)
  vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
  vim.api.nvim_buf_set_var(bufnr, "octo_diff_props", {
    path = opts.path,
    split = string.upper(opts.split),
  })
  return bufnr
end

function M.load_null_buffers(left_winid, right_winid)
  M.load_null_buffer(left_winid)
  M.load_null_buffer(right_winid)
end

function M.load_null_buffer(winid)
  local bn = M._get_null_buffer()
  if vim.api.nvim_win_is_valid(winid) then
    vim.api.nvim_win_set_buf(winid, bn)
  end
  M._configure_buffer(bn)
end

function M._get_null_buffer()
  local msg = "Loading ..."
  local bn = M._null_buffer[msg]
  if not bn or vim.api.nvim_buf_is_loaded(bn) then
    local nbn = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_buf_set_lines(nbn, 0, -1, false, { msg })
    local bufname = utils.path_join { "octo", "null" }
    vim.api.nvim_buf_set_option(nbn, "modified", false)
    vim.api.nvim_buf_set_option(nbn, "modifiable", false)
    local ok = pcall(vim.api.nvim_buf_set_name, nbn, bufname)
    if not ok then
      utils.wipe_named_buffer(bufname)
      vim.api.nvim_buf_set_name(nbn, bufname)
    end
    M._null_buffer[msg] = nbn
  end
  return M._null_buffer[msg]
end

function M._configure_windows(left_winid, right_winid)
  for _, id in ipairs { left_winid, right_winid } do
    for k, v in pairs(FileEntry.winopts) do
      vim.api.nvim_win_set_option(id, k, v)
    end
  end
end

function M._configure_buffer(bufid)
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
