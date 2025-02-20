-- Heavily derived from `diffview.nvim`: https://github.com/sindrets/diffview.nvim/blob/main/lua/diffview/file-panel.lua
-- https://github.com/sindrets/diffview.nvim/blob/main/lua/diffview/file-panel.lua

local utils = require "octo.utils"
local config = require "octo.config"
local constants = require "octo.constants"
local renderer = require "octo.reviews.renderer"
local M = {}

local name_counter = 1
local header_size = 1

---@class FilePanel
---@field files FileEntry[]
---@field size integer
---@field bufid integer
---@field winid integer
---@field render_data RenderData
local FilePanel = {}
FilePanel.__index = FilePanel

FilePanel.winopts = {
  relativenumber = false,
  number = false,
  list = false,
  winfixwidth = true,
  winfixheight = true,
  foldenable = false,
  spell = false,
  wrap = false,
  cursorline = true,
  signcolumn = "yes",
  foldmethod = "manual",
  foldcolumn = "0",
  scrollbind = false,
  cursorbind = false,
  diff = false,
  winhl = table.concat({
    "EndOfBuffer:OctoEndOfBuffer",
    "Normal:OctoNormal",
    "VertSplit:OctoVertSplit",
    "SignColumn:OctoNormal",
    "StatusLine:OctoStatusLine",
    "StatusLineNC:OctoStatuslineNC",
  }, ","),
}

FilePanel.bufopts = {
  swapfile = false,
  buftype = "nofile",
  modifiable = false,
  filetype = "octo_panel",
  bufhidden = "hide",
}

---FilePanel constructor.
---@param files FileEntry[]
---@return FilePanel
function FilePanel:new(files)
  local conf = config.values
  local this = {
    files = files,
    size = conf.file_panel.size,
  }

  setmetatable(this, self)
  return this
end

function FilePanel:is_open()
  local valid = self.winid and vim.api.nvim_win_is_valid(self.winid)
  if not valid then
    self.winid = nil
  end
  return valid
end

function FilePanel:is_focused()
  return self:is_open() and vim.api.nvim_get_current_win() == self.winid
end

function FilePanel:focus(open_if_closed)
  if self:is_open() then
    vim.api.nvim_set_current_win(self.winid)
  elseif open_if_closed then
    self:open()
  end
end

function FilePanel:open()
  if not self:buf_loaded() then
    self:init_buffer()
  end
  if self:is_open() then
    return
  end

  local conf = config.values
  self.size = conf.file_panel.size
  --vim.cmd("wincmd H")
  --vim.cmd("vsp")
  --vim.cmd("vertical resize " .. self.width)
  vim.cmd "sp"
  vim.cmd "wincmd J"
  vim.cmd("resize " .. self.size)
  self.winid = vim.api.nvim_get_current_win()

  for k, v in pairs(FilePanel.winopts) do
    vim.api.nvim_win_set_option(self.winid, k, v)
  end

  vim.cmd("buffer " .. self.bufid)
  vim.cmd ":wincmd ="
end

function FilePanel:close()
  if self:is_open() and #vim.api.nvim_tabpage_list_wins(0) > 1 then
    pcall(vim.api.nvim_win_hide, self.winid)
  end
end

function FilePanel:destroy()
  if self:buf_loaded() then
    self:close()
    pcall(vim.api.nvim_buf_delete, self.bufid, { force = true })
  else
    self:close()
  end
end

function FilePanel:toggle()
  if self:is_open() then
    self:close()
  else
    self:open()
  end
end

function FilePanel:buf_loaded()
  return self.bufid and vim.api.nvim_buf_is_loaded(self.bufid)
end

function FilePanel:init_buffer()
  local bn = vim.api.nvim_create_buf(false, false)

  for k, v in pairs(FilePanel.bufopts) do
    vim.api.nvim_buf_set_option(bn, k, v)
  end

  local bufname = "OctoChangedFiles-" .. name_counter
  name_counter = name_counter + 1
  local ok = pcall(vim.api.nvim_buf_set_name, bn, bufname)
  if not ok then
    utils.wipe_named_buffer(bufname)
    vim.api.nvim_buf_set_name(bn, bufname)
  end
  self.bufid = bn
  self.render_data = renderer.RenderData:new(bufname)
  utils.apply_mappings("file_panel", self.bufid)
  self:render()
  self:redraw()

  return bn
end

function FilePanel:get_file_at_cursor()
  if not (self:is_open() and self:buf_loaded()) then
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(self.winid)
  local line = cursor[1]
  return self.files[utils.clamp(line - header_size, 1, #self.files)]
end

function FilePanel:highlight_file(file)
  if not (self:is_open() and self:buf_loaded()) then
    return
  end

  for i, f in ipairs(self.files) do
    if f == file then
      pcall(vim.api.nvim_win_set_cursor, self.winid, { i + header_size, 0 })
      vim.api.nvim_buf_clear_namespace(self.bufid, constants.OCTO_FILE_PANEL_NS, 0, -1)
      vim.api.nvim_buf_add_highlight(
        self.bufid,
        constants.OCTO_FILE_PANEL_NS,
        "OctoFilePanelSelectedFile",
        i + header_size - 1,
        0,
        -1
      )
    end
  end
end

function FilePanel:highlight_prev_file()
  if not (self:is_open() and self:buf_loaded()) or #self.files == 0 then
    return
  end

  local cur = self:get_file_at_cursor()
  for i, f in ipairs(self.files) do
    if f == cur then
      local line = utils.clamp(i + header_size - 1, header_size + 1, #self.files + header_size)
      pcall(vim.api.nvim_win_set_cursor, self.winid, { line, 0 })
    end
  end
end

function FilePanel:highlight_next_file()
  if not (self:is_open() and self:buf_loaded()) or #self.files == 0 then
    return
  end

  local cur = self:get_file_at_cursor()
  for i, f in ipairs(self.files) do
    if f == cur then
      local line = utils.clamp(i + header_size + 1, header_size, #self.files + header_size)
      pcall(vim.api.nvim_win_set_cursor, self.winid, { line, 0 })
    end
  end
end

function FilePanel:render()
  local current_review = require("octo.reviews").get_current_review()
  if not current_review then
    return
  end

  if not self.render_data then
    return
  end

  self.render_data:clear()
  local line_idx = 0
  local lines = self.render_data.lines
  local add_hl = function(...)
    self.render_data:add_hl(...)
  end

  local conf = config.values
  local strlen = vim.fn.strlen
  local s = "Files changed"
  add_hl("OctoFilePanelTitle", line_idx, 0, #s)
  local change_count = string.format("%s%d%s", conf.left_bubble_delimiter, #self.files, conf.right_bubble_delimiter)
  add_hl("OctoBubbleDelimiterYellow", line_idx, strlen(s) + 1, strlen(s) + 1 + strlen(conf.left_bubble_delimiter))
  add_hl(
    "OctoBubbleYellow",
    line_idx,
    strlen(s) + 1 + strlen(conf.left_bubble_delimiter),
    strlen(s) + 1 + strlen(change_count) - strlen(conf.right_bubble_delimiter)
  )
  add_hl(
    "OctoBubbleDelimiterYellow",
    line_idx,
    strlen(s) + 1 + strlen(change_count) - strlen(conf.right_bubble_delimiter),
    strlen(s) + 1 + strlen(change_count)
  )
  s = s .. " " .. change_count
  table.insert(lines, s)
  line_idx = line_idx + 1

  local max_changes_length = 0
  local max_path_length = 0
  for _, file in ipairs(self.files) do
    local diffstat = utils.diffstat(file.stats)
    max_changes_length = math.max(max_changes_length, string.len(diffstat.total))
    max_path_length = math.max(max_path_length, string.len(file.path))
  end

  for _, file in ipairs(self.files) do
    local offset = 0
    s = ""

    -- diffstat histogram
    if file.stats then
      local diffstat = utils.diffstat(file.stats)

      local file_changes_length = string.len(diffstat.total)
      s = string.rep(" ", max_changes_length - file_changes_length) .. diffstat.total .. " "
      offset = #s
      if diffstat.additions > 0 then
        s = s .. string.rep("■", diffstat.additions)
        add_hl("OctoDiffstatAdditions", line_idx, offset, offset + (3 * diffstat.additions))
        offset = offset + (3 * diffstat.additions)
      end
      if diffstat.deletions > 0 then
        s = s .. string.rep("■", diffstat.deletions)
        add_hl("OctoDiffstatDeletions", line_idx, offset, offset + (3 * diffstat.deletions))
        offset = offset + (3 * diffstat.deletions)
      end
      if diffstat.neutral > 0 then
        s = s .. string.rep("■", diffstat.neutral)
        add_hl("OctoDiffstatNeutral", line_idx, offset, offset + (3 * diffstat.neutral))
        offset = offset + (3 * diffstat.neutral)
      end
    end

    -- status
    add_hl(renderer.get_git_hl(file.status), line_idx, offset + 1, offset + 2)
    s = s .. " " .. file.status
    offset = #s

    -- viewer viewed state
    if not file.viewed_state then
      file.viewed_state = "UNVIEWED"
    end
    local viewerViewedStateIcon = utils.viewed_state_map[file.viewed_state].icon
    local viewerViewedStateHl = utils.viewed_state_map[file.viewed_state].hl
    s = s .. " " .. viewerViewedStateIcon
    add_hl(viewerViewedStateHl, line_idx, offset + 1, offset + 4)
    offset = #s

    -- icon
    local icon = renderer.get_file_icon(file.basename, file.extension, self.render_data, line_idx, offset)
    offset = offset + #icon

    -- file path
    add_hl("OctoFilePanelFileName", line_idx, offset, offset + #file.path)
    s = s .. icon .. file.path

    -- thread counts
    local active, resolved, outdated, pending = M.thread_counts(file.path)
    if active > 0 or resolved > 0 or pending > 0 or outdated > 0 then
      -- white space to align count columns
      offset = #s + 1
      s = s .. string.rep(" ", max_path_length + 1 - string.len(file.path))
    end
    local segments = {
      { count = active, prefix = "active: ", center_hl = "OctoBubbleBlue", delimiter_hl = "OctoBubbleDelimiterBlue" },
      {
        count = pending,
        prefix = "pending: ",
        center_hl = "OctoBubbleYellow",
        delimiter_hl = "OctoBubbleDelimiterYellow",
      },
      {
        count = resolved,
        prefix = "resolved: ",
        center_hl = "OctoBubbleGreen",
        delimiter_hl = "OctoBubbleDelimiterGreen",
      },
      {
        count = outdated,
        prefix = "outdated: ",
        center_hl = "OctoBubbleRed",
        delimiter_hl = "OctoBubbleDelimiterRed",
      },
    }
    for _, segment in ipairs(segments) do
      if segment.count > 0 then
        offset = #s + 1
        local str = string.format(
          "%s%s%d%s",
          segment.prefix,
          conf.left_bubble_delimiter,
          segment.count,
          conf.right_bubble_delimiter
        )
        add_hl("OctoMissingDetails", line_idx, offset, offset + string.len(segment.prefix))
        add_hl(
          segment.delimiter_hl,
          line_idx,
          offset + strlen(segment.prefix),
          offset + strlen(segment.prefix) + strlen(conf.left_bubble_delimiter)
        )
        add_hl(
          segment.center_hl,
          line_idx,
          offset + strlen(segment.prefix) + strlen(conf.left_bubble_delimiter),
          offset + strlen(str) - strlen(conf.right_bubble_delimiter)
        )
        add_hl(
          segment.delimiter_hl,
          line_idx,
          offset + strlen(str) - strlen(conf.right_bubble_delimiter),
          offset + strlen(str)
        )
        s = s .. " " .. str
      end
    end

    table.insert(lines, s)
    line_idx = line_idx + 1
  end

  local right = current_review.layout.right
  local left = current_review.layout.left
  local extra_info = { left:abbrev() .. ".." .. right:abbrev() }
  table.insert(lines, "")
  line_idx = line_idx + 1

  s = "Showing changes for:"
  add_hl("DiffviewFilePanelTitle", line_idx, 0, #s)
  table.insert(lines, s)
  line_idx = line_idx + 1

  for _, arg in ipairs(extra_info) do
    s = arg
    add_hl("DiffviewFilePanelPath", line_idx, 0, #s)
    table.insert(lines, s)
    line_idx = line_idx + 1
  end
end

function FilePanel:redraw()
  if not self.render_data then
    return
  end
  renderer.render(self.bufid, self.render_data)
end

M.FilePanel = FilePanel

function M.threads_for_path(path)
  local current_review = require("octo.reviews").get_current_review()
  if not current_review then
    return {}
  end
  local threads = {}
  for _, thread in pairs(current_review.threads) do
    if path == thread.path then
      table.insert(threads, thread)
    end
  end
  return threads
end

function M.thread_counts(path)
  local threads = M.threads_for_path(path)
  local resolved = 0
  local outdated = 0
  local pending = 0
  local active = 0
  for _, thread in pairs(threads) do
    if not thread.isOutdated and not thread.isResolved and #thread.comments.nodes > 0 then
      active = active + 1
    end
    if thread.isOutdated and #thread.comments.nodes > 0 then
      outdated = outdated + 1
    end
    if thread.isResolved and #thread.comments.nodes > 0 then
      resolved = resolved + 1
    end
    for _, comment in ipairs(thread.comments.nodes) do
      local review = comment.pullRequestReview
      if not utils.is_blank(review) and review.state == "PENDING" and not utils.is_blank(utils.trim(comment.body)) then
        pending = pending + 1
      end
    end
  end
  return active, resolved, outdated, pending
end

function M.next_thread()
  local bufnr = vim.api.nvim_get_current_buf()
  local _, path = utils.get_split_and_path(bufnr)
  local current_line = vim.fn.line "."
  local candidate = math.huge
  if path then
    for _, thread in ipairs(M.threads_for_path(path)) do
      if thread.startLine > current_line and thread.startLine < candidate then
        candidate = thread.startLine
      end
    end
  end
  if candidate < math.huge then
    vim.cmd(":" .. candidate)
  end
end

function M.prev_thread()
  local bufnr = vim.api.nvim_get_current_buf()
  local _, path = utils.get_split_and_path(bufnr)
  local current_line = vim.fn.line "."
  local candidate = -1
  if path then
    for _, thread in ipairs(M.threads_for_path(path)) do
      if thread.originalLine < current_line and thread.originalLine > candidate then
        candidate = thread.originalLine
      end
    end
  end
  if candidate > -1 then
    vim.cmd(":" .. candidate)
  end
end

return M
