local util = require("octo.util")
local writers = require("octo.writers")
local constants = require("octo.constants")
local format = string.format
local api = vim.api

local M = {}

function M.place(name, bufnr, line)
  -- 0-index based wrapper
  pcall(vim.fn.sign_place, 0, "octo_ns", name, bufnr, {lnum = line + 1})
end

function M.unplace(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()
  pcall(vim.fn.sign_unplace, "octo_ns", {buffer = bufnr})
end

function M.place_signs(bufnr, start_line, end_line, is_dirty)
  local dirty_mod = is_dirty and "dirty" or "clean"

  if start_line == end_line or end_line < start_line then
    M.place(format("octo_%s_line", dirty_mod), bufnr, start_line)
  else
    M.place(format("octo_%s_block_start", dirty_mod), bufnr, start_line)
    M.place(format("octo_%s_block_end", dirty_mod), bufnr, end_line)
  end
  if start_line + 1 < end_line then
    for j = start_line + 1, end_line - 1, 1 do
      M.place(format("octo_%s_block_middle", dirty_mod), bufnr, j)
    end
  end
end

function M.place_coment_signs()
  local bufnr = api.nvim_get_current_buf()
  M.unplace(bufnr)
  local status, props = pcall(api.nvim_buf_get_var, bufnr, "OctoDiffProps")
  if status and props then
    local bufname_prefix = format("%s:", string.gsub(props.bufname, "/file/", "/comment/"))
    local review_comments = require"octo.reviews".review_comments
    local comment_keys = vim.tbl_keys(review_comments)
    for _, comment_key in ipairs(comment_keys) do
      if vim.startswith(comment_key, bufname_prefix) then
        local comment = review_comments[comment_key]
          for line = comment.startLine, comment.line do
            M.place("octo_comment", bufnr, line - 1)
          end
      end
    end
  end
end

function M.render_signcolumn(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()
  local ft = api.nvim_buf_get_option(bufnr, "filetype")
  if not vim.startswith(ft, "octo_") then
    return
  end

  local issue_dirty = false

  -- update comment metadata (lines, etc.)
  util.update_issue_metadata(bufnr)

  -- clear all signs
  M.unplace(bufnr)

  -- clear virtual texts
  api.nvim_buf_clear_namespace(bufnr, constants.OCTO_EMPTY_MSG_VT_NS, 0, -1)

  local start_line, end_line
  if ft == "octo_issue" then
    -- title
    local title = api.nvim_buf_get_var(bufnr, "title")
    if title["dirty"] then
      issue_dirty = true
    end
    start_line = title["start_line"]
    end_line = title["end_line"]
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
      writers.write_virtual_text(bufnr, constants.OCTO_EMPTY_MSG_VT_NS, start_line, desc_vt)
    end
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
      writers.write_virtual_text(bufnr, constants.OCTO_EMPTY_MSG_VT_NS, start_line, comment_vt)
    end
  end

  -- reset modified option
  if not issue_dirty then
    api.nvim_buf_set_option(bufnr, "modified", false)
  end
end

return M
