-- Heavily derived from `diffview.nvim`:
-- https://github.com/sindrets/diffview.nvim/blob/main/lua/diffview/renderer.lua
--
local M = {}
local web_devicons ---@module "nvim-web-devicons"
local config = require "octo.config"
local vim = vim

---@class HlData
---@field group string
---@field line_idx integer
---@field first integer
---@field last integer

---@class RenderData
---@field lines string[]
---@field hl HlData[]
---@field namespace integer
local RenderData = {}
RenderData.__index = RenderData

---RenderData constructor.
---@return RenderData
function RenderData:new(ns_name)
  local this = {
    lines = {},
    hl = {},
    namespace = vim.api.nvim_create_namespace(ns_name),
  }
  setmetatable(this, self)
  return this
end

function RenderData:add_hl(group, line_idx, first, last)
  table.insert(self.hl, {
    group = group,
    line_idx = line_idx,
    first = first,
    last = last,
  })
end

function RenderData:clear()
  self.lines = {}
  self.hl = {}
end

---Render the given render data to the given buffer.
---@param bufid integer
---@param data RenderData
function M.render(bufid, data)
  if not vim.api.nvim_buf_is_loaded(bufid) then
    return
  end

  local was_modifiable = vim.bo[bufid].modifiable
  vim.bo[bufid].modifiable = true

  vim.api.nvim_buf_set_lines(bufid, 0, -1, false, data.lines)
  vim.api.nvim_buf_clear_namespace(bufid, data.namespace, 0, -1)
  for _, hl in ipairs(data.hl) do
    vim.api.nvim_buf_set_extmark(bufid, data.namespace, hl.line_idx, hl.first, {
      end_col = hl.last,
      hl_group = hl.group,
    })
  end

  vim.bo[bufid].modifiable = was_modifiable
end

local git_status_hl_map = {
  [" "] = "OctoStatusAdded",
  ["A"] = "OctoStatusAdded",
  ["?"] = "OctoStatusAdded",
  ["M"] = "OctoStatusModified",
  ["R"] = "OctoStatusRenamed",
  ["C"] = "OctoStatusCopied",
  ["T"] = "OctoStatusTypeChanged",
  ["U"] = "OctoStatusUnmerged",
  ["X"] = "OctoStatusUnknown",
  ["D"] = "OctoStatusDeleted",
  ["B"] = "OctoStatusBroken",
}

---@param status string
function M.get_git_hl(status)
  return git_status_hl_map[status]
end

---@param name string
---@param ext string
---@param render_data any
---@param line_idx integer
---@param offset integer
function M.get_file_icon(name, ext, render_data, line_idx, offset)
  local use_icons = config.values.file_panel.use_icons
  if not use_icons then
    return " "
  end

  if not web_devicons then
    web_devicons = require "nvim-web-devicons"
  end

  local icon, hl = web_devicons.get_icon(name, ext)

  if icon then
    if hl then
      render_data:add_hl(hl, line_idx, offset, offset + string.len(icon) + 1)
    end
    return icon .. " "
  end

  return ""
end

M.RenderData = RenderData
return M
