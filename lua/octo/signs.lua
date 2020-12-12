local format = string.format

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
	pcall(vim.fn.sign_place, 0, 'octo_ns', name, bufnr, {lnum=line+1})
end

function M.unplace(bufnr)
	pcall(vim.fn.sign_unplace, 'octo_ns', {buffer=bufnr})
end

function M.place_signs(bufnr, start_line, end_line, is_dirty)
	local dirty_mod = is_dirty and 'dirty' or 'clean'

	if start_line == end_line or end_line < start_line then
		M.place(format('%s_line', dirty_mod), bufnr, start_line)
	else
		M.place(format('%s_block_start', dirty_mod), bufnr, start_line)
		M.place(format('%s_block_end', dirty_mod), bufnr, end_line)
	end
	if start_line+1 < end_line then
		for j=start_line+1,end_line-1,1 do
			M.place(format('%s_block_middle', dirty_mod), bufnr, j)
		end
	end
end

return M
