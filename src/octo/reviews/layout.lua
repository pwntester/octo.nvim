-- Heavily derived from `diffview.nvim`:
-- https://github.com/sindrets/diffview.nvim/blob/main/lua/diffview/view.lua
--
local FilePanel = require("octo.reviews.file-panel").FilePanel
local utils = require "octo.utils"
local file_entry = require "octo.reviews.file-entry"

local M = {}

M._views = {}

local win_reset_opts = {
  diff = false,
  cursorbind = false,
  scrollbind = false,
}

---@class Layout
---@field tabpage integer
---@field left Rev
---@field right Rev
---@field file_panel FilePanel
---@field left_winid integer
---@field right_winid integer
---@field files FileEntry[]
---@field file_idx integer
---@field ready boolean
local Layout = {}
Layout.__index = Layout

---Layout constructor
---@return Layout
function Layout:new(opt)
  local this = {
    left = opt.left,
    right = opt.right,
    files = opt.files,
    file_idx = 1,
    ready = false,
  }
  this.file_panel = FilePanel:new(this.files)
  setmetatable(this, self)
  return this
end

function Layout:open(review)
  vim.cmd "tab split"
  self.tabpage = vim.api.nvim_get_current_tabpage()
  require("octo.reviews").reviews[tostring(self.tabpage)] = review
  self:init_layout()

  local file = self:cur_file()
  if file then
    self:set_file(file)
  else
    self:file_safeguard()
  end
  self.ready = true
end

function Layout:close()
  for _, file in ipairs(self.files) do
    file:destroy()
  end

  --self.file_panel:destroy()

  if self.tabpage and vim.api.nvim_tabpage_is_valid(self.tabpage) then
    local pagenr = vim.api.nvim_tabpage_get_number(self.tabpage)
    pcall(vim.cmd, "tabclose " .. pagenr)
  end
end

function Layout:init_layout()
  self.left_winid = vim.api.nvim_get_current_win()
  vim.cmd "belowright vsp"
  self.right_winid = vim.api.nvim_get_current_win()
  self.file_panel:open()
end

function Layout:cur_file()
  if #self.files > 0 then
    return self.files[utils.clamp(self.file_idx, 1, #self.files)]
  end
  return nil
end

function Layout:next_file()
  self:ensure_layout()
  if self:file_safeguard() then
    return
  end

  if #self.files > 1 then
    local cur = self:cur_file()
    if cur then
      cur:detach_buffers()
    end
    self.file_idx = self.file_idx % #self.files + 1
    vim.cmd "diffoff!"
    -- Load file diffs in layout wins
    self.files[self.file_idx]:load_buffers(self.left_winid, self.right_winid)
    self.file_panel:highlight_file(self:cur_file())
  end
end

function Layout:prev_file()
  self:ensure_layout()
  if self:file_safeguard() then
    return
  end

  if #self.files > 1 then
    local cur = self:cur_file()
    if cur then
      cur:detach_buffers()
    end
    self.file_idx = (self.file_idx - 2) % #self.files + 1
    vim.cmd "diffoff!"
    self.files[self.file_idx]:load_buffers(self.left_winid, self.right_winid)
    self.file_panel:highlight_file(self:cur_file())
  end
end

-- sets selected file
function Layout:set_file(file, focus)
  self:ensure_layout()
  if self:file_safeguard() or not file then
    return
  end
  local found = false
  for i, f in ipairs(self.files) do
    if f == file then
      found = true
      self.file_idx = i
      break
    end
  end
  if found then
    if not file.left_lines or not file.right_lines then
      local result = file:fetch()
      if not result then
        vim.api.nvim_err_writeln("Timeout fetching " .. file.path)
        return
      end
    end
    local cur = self:cur_file()
    if cur then
      cur:detach_buffers()
    end
    vim.cmd "diffoff!"
    local selected_file = self.files[self.file_idx]

    selected_file:load_buffers(self.left_winid, self.right_winid)

    -- highlight file in file panel
    self.file_panel:highlight_file(self:cur_file())

    -- set focus on specified window
    if focus == "right" then
      vim.api.nvim_set_current_win(self.right_winid)
    else
      vim.api.nvim_set_current_win(self.left_winid)
    end
  end
end

---Update the file list, including stats and status for all files.
function Layout:update_files()
  self.file_panel.files = self.files
  self.file_panel:render()
  self.file_panel:redraw()
  local file = self:cur_file()
  self:set_file(file)
  self.update_needed = false
end

---Checks the state of the view layout.
---@return table
function Layout:validate_layout()
  local state = {
    tabpage = vim.api.nvim_tabpage_is_valid(self.tabpage),
    left_win = vim.api.nvim_win_is_valid(self.left_winid),
    right_win = vim.api.nvim_win_is_valid(self.right_winid),
  }
  state.valid = state.tabpage and state.left_win and state.right_win
  return state
end

---Recover the layout after the user has messed it up.
---@param state table
function Layout:recover_layout(state)
  self.ready = false
  if not state.tabpage then
    vim.cmd "tab split"
    self.tabpage = vim.api.nvim_get_current_tabpage()
    self.file_panel:close()
    self:init_layout()
    self.ready = true
    return
  end

  vim.api.nvim_set_current_tabpage(self.tabpage)
  self.file_panel:close()

  if not state.left_win and not state.right_win then
    self:init_layout()
  elseif not state.left_win then
    vim.api.nvim_set_current_win(self.right_winid)
    vim.cmd "aboveleft vsp"
    self.left_winid = vim.api.nvim_get_current_win()
    self.file_panel:open()
    --self:set_file(self:cur_file(), "right")
  elseif not state.right_win then
    vim.api.nvim_set_current_win(self.left_winid)
    vim.cmd "belowright vsp"
    self.right_winid = vim.api.nvim_get_current_win()
    self.file_panel:open()
    --self:set_file(self:cur_file(), "left")
  end

  self.ready = true
end

---Ensure both left and right windows exist in the view's tabpage.
function Layout:ensure_layout()
  local state = self:validate_layout()
  if not state.valid then
    self:recover_layout(state)
  end
end

---Ensures there are files to load, and loads the null buffer otherwise.
---@return boolean
function Layout:file_safeguard()
  if #self.files == 0 then
    local cur = self:cur_file()
    if cur then
      cur:detach_buffers()
    end
    file_entry.load_null_buffers(self.left_winid, self.right_winid)
    return true
  end
  return false
end

function Layout:on_enter()
  if self.ready then
    self:update_files()
  end

  local file = self:cur_file()
  if file then
    file:attach_buffers()
  end
end

function Layout:on_leave()
  local file = self:cur_file()
  if file then
    file:detach_buffers()
  end
end

function Layout:on_win_leave()
  if self.ready and vim.api.nvim_tabpage_is_valid(self.tabpage) then
    self:fix_foreign_windows()
  end
end

---Disable unwanted options in all windows not part of the view.
function Layout:fix_foreign_windows()
  local win_ids = vim.api.nvim_tabpage_list_wins(self.tabpage)
  for _, id in ipairs(win_ids) do
    if not (id == self.file_panel.winid or id == self.left_winid or id == self.right_winid) then
      for k, v in pairs(win_reset_opts) do
        vim.api.nvim_win_set_option(id, k, v)
      end
    end
  end
end

M.Layout = Layout

return M
