local config = require "octo.config"

local M = {}

function M.setup()
  local conf = config.get_config()

  vim.cmd(string.format("sign define octo_thread text=%s texthl=OctoBlue", conf.comment_icon))
  vim.cmd(string.format("sign define octo_thread_resolved text=%s  texthl=OctoGreen", conf.comment_icon))
  vim.cmd(string.format("sign define octo_thread_outdated text=%s  texthl=OctoRed", conf.comment_icon))
  vim.cmd(string.format("sign define octo_thread_pending text=%s texthl=OctoYellow", conf.comment_icon))
  vim.cmd(string.format("sign define octo_thread_resolved_pending text=%s texthl=OctoYellow", conf.comment_icon))
  vim.cmd(string.format("sign define octo_thread_outdated_pending text=%s texthl=OctoYellow", conf.comment_icon))

  vim.cmd [[sign define octo_comment_range numhl=OctoGreen]]
  vim.cmd [[sign define octo_clean_block_start text=┌ linehl=OctoEditable]]
  vim.cmd [[sign define octo_clean_block_end text=└ linehl=OctoEditable]]
  vim.cmd [[sign define octo_dirty_block_start text=┌ texthl=OctoDirty linehl=OctoEditable]]
  vim.cmd [[sign define octo_dirty_block_end text=└ texthl=OctoDirty linehl=OctoEditable]]
  vim.cmd [[sign define octo_dirty_block_middle text=│ texthl=OctoDirty linehl=OctoEditable]]
  vim.cmd [[sign define octo_clean_block_middle text=│ linehl=OctoEditable]]
  vim.cmd [[sign define octo_clean_line text=[ linehl=OctoEditable]]
  vim.cmd [[sign define octo_dirty_line text=[ texthl=OctoDirty linehl=OctoEditable]]
end

function M.place(name, bufnr, line)
  -- 0-index based wrapper
  if not line then
    return
  end
  pcall(vim.fn.sign_place, 0, "octo_ns", name, bufnr, { lnum = line + 1 })
end

function M.unplace(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  pcall(vim.fn.sign_unplace, "octo_ns", { buffer = bufnr })
end

function M.place_signs(bufnr, start_line, end_line, is_dirty)
  if not start_line or not end_line then
    return
  end
  local dirty_mod = is_dirty and "dirty" or "clean"

  if start_line == end_line or end_line < start_line then
    M.place(string.format("octo_%s_line", dirty_mod), bufnr, start_line)
  else
    M.place(string.format("octo_%s_block_start", dirty_mod), bufnr, start_line)
    M.place(string.format("octo_%s_block_end", dirty_mod), bufnr, end_line)
  end
  if start_line + 1 < end_line then
    for j = start_line + 1, end_line - 1, 1 do
      M.place(string.format("octo_%s_block_middle", dirty_mod), bufnr, j)
    end
  end
end

return M
