local util = require("octo.util")
local constants = require("octo.constants")
local format = string.format
local api = vim.api

local M = {}

function M.setup()
  -- sign definitions
  vim.cmd [[ sign define clean_block_start text=┌ ]]
  vim.cmd [[ sign define clean_block_end text=└ ]]
  vim.cmd [[ sign define dirty_block_start text=┌ texthl=OctoNvimDirty ]]
  vim.cmd [[ sign define dirty_block_end text=└ texthl=OctoNvimDirty ]]
  vim.cmd [[ sign define dirty_block_middle text=│ texthl=OctoNvimDirty ]]
  vim.cmd [[ sign define clean_block_middle text=│ ]]
  vim.cmd [[ sign define clean_line text=[ ]]
  vim.cmd [[ sign define dirty_line text=[ texthl=OctoNvimDirty ]]
end

function M.place(name, bufnr, line)
  -- 0-index based wrapper
  pcall(vim.fn.sign_place, 0, "octo_ns", name, bufnr, {lnum = line + 1})
end

function M.unplace(bufnr)
  pcall(vim.fn.sign_unplace, "octo_ns", {buffer = bufnr})
end

function M.place_signs(bufnr, start_line, end_line, is_dirty)
  local dirty_mod = is_dirty and "dirty" or "clean"

  if start_line == end_line or end_line < start_line then
    M.place(format("%s_line", dirty_mod), bufnr, start_line)
  else
    M.place(format("%s_block_start", dirty_mod), bufnr, start_line)
    M.place(format("%s_block_end", dirty_mod), bufnr, end_line)
  end
  if start_line + 1 < end_line then
    for j = start_line + 1, end_line - 1, 1 do
      M.place(format("%s_block_middle", dirty_mod), bufnr, j)
    end
  end
end

function M.render_signcolumn(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()
  local bufname = api.nvim_buf_get_name(bufnr)
  if not vim.startswith(bufname, "octo://") then
    return
  end

  local issue_dirty = false

  -- update comment metadata (lines, etc.)
  util.update_issue_metadata(bufnr)

  -- clear all signs
  M.unplace(bufnr)

  -- clear virtual texts
  api.nvim_buf_clear_namespace(bufnr, constants.OCTO_EMPTY_MSG_VT_NS, 0, -1)

  -- title
  local title = api.nvim_buf_get_var(bufnr, "title")
  if title["dirty"] then
    issue_dirty = true
  end
  local start_line = title["start_line"]
  local end_line = title["end_line"]
  M.place_signs(bufnr, start_line, end_line, title["dirty"])

  -- description
  local desc = api.nvim_buf_get_var(bufnr, "description")
  if desc.dirty then
    issue_dirty = true
  end
  start_line = desc["start_line"]
  end_line = desc["end_line"]
  M.place_signs(bufnr, start_line, end_line, desc.dirty)

  -- description virtual text
  if util.is_blank(desc["body"]) then
    local desc_vt = {{constants.NO_BODY_MSG, "OctoNvimEmpty"}}
    api.nvim_buf_set_virtual_text(bufnr, constants.OCTO_EMPTY_MSG_VT_NS, start_line, desc_vt, {})
  end

  -- comments
  local comments = api.nvim_buf_get_var(bufnr, "comments")
  for _, c in ipairs(comments) do
    if c.dirty then
      issue_dirty = true
    end
    start_line = c["start_line"]
    end_line = c["end_line"]
    M.place_signs(bufnr, start_line, end_line, c.dirty)

    -- comment virtual text
    if util.is_blank(c["body"]) then
      local comment_vt = {{constants.NO_BODY_MSG, "OctoNvimEmpty"}}
      api.nvim_buf_set_virtual_text(bufnr, constants.OCTO_EMPTY_MSG_VT_NS, start_line, comment_vt, {})
    end
  end

  -- reset modified option
  if not issue_dirty then
    api.nvim_buf_set_option(bufnr, "modified", false)
  end
end

return M
