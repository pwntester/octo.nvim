local curl = require('octo.curl')
local vim = vim
local api = vim.api
local max = math.max
local deepcopy = vim.deepcopy
local format = string.format
local log = require('octo.log')
local json = {
	parse = vim.fn.json_decode;
	stringify = vim.fn.json_encode;
}

-- constants
local NO_BODY_MSG = 'No description provided.'
local HIGHLIGHT_NAME_PREFIX = "octo"
local HIGHLIGHT_CACHE = {}
local HIGHLIGHT_MODE_NAMES = {
	background = "mb";
	foreground = "mf";
}

-- curl opts
local curl_opts = {
  credentials = vim.fn.getenv('OCTO_GITHUB_TOKEN');
	headers = {
		['Accept']       = 'application/vnd.github.v3+json',
		['Content-Type'] = 'application/json'
	}
}

-- autocommands
vim.cmd [[ augroup octo_autocmds ]]
vim.cmd [[ autocmd!]]
-- vim.cmd [[ au BufEnter github://* nested lua require'octo'.show_details_win() ]]
-- vim.cmd [[ au BufLeave github://* nested lua require'octo'.close_details_win() ]]
-- vim.cmd [[ au WinLeave * nested lua require'octo'.close_details_win() ]]
vim.cmd [[ au TextChanged github://* lua require"octo".render_signcolumn() ]]
vim.cmd [[ au TextChangedI github://* lua require"octo".render_signcolumn() ]]
vim.cmd [[ au BufReadCmd github://* lua require"octo".load_issue() ]]
vim.cmd [[ au BufWriteCmd github://* lua require"octo".save_issue() ]]
vim.cmd [[ augroup END ]]

local function is_blank(s)
	return not(s ~= nil and s:match("%S") ~= nil)
end

local function check_error(status, resp)
	if vim.tbl_contains({100,200,201}, status) then
		return false
	elseif resp.message then
		api.nvim_err_writeln('Error ('..status..'): '..resp.message)
		return true
	else
		print('Unexpected status:', status, resp)
		return true
	end
end

local function sign_place(name, bufnr, line)
	-- 0-index based wrapper
	pcall(vim.fn.sign_place, 0, 'octo_ns', name, bufnr, {lnum=line+1})
end

local function sign_unplace(bufnr)
	pcall(vim.fn.sign_unplace, 'octo_ns', {buffer=bufnr})
end

local function place_signs(bufnr, start_line, end_line, is_dirty)
	local dirty_mod = is_dirty and 'dirty' or 'clean'

	if start_line == end_line or end_line < start_line then
		sign_place(format('%s_line', dirty_mod), bufnr, start_line)
	else
		sign_place(format('%s_block_start', dirty_mod), bufnr, start_line)
		sign_place(format('%s_block_end', dirty_mod), bufnr, end_line)
	end
	if start_line+1 < end_line then
		for j=start_line+1,end_line-1,1 do
			sign_place(format('%s_block_middle', dirty_mod), bufnr, j)
		end
	end
end

local function highlight(bufnr, hls)
	for _, hl in ipairs(hls) do
		api.nvim_buf_add_highlight(bufnr, octo_hl_ns, hl.name, hl.line, hl.start, hl['end'])
	end
end

-- from norcalli's colorizer
local function make_highlight_name(rgb, mode)
	return table.concat({HIGHLIGHT_NAME_PREFIX, HIGHLIGHT_MODE_NAMES[mode], rgb}, '_')
end

-- from norcalli's colorizer
local function color_is_bright(r, g, b)
	-- Counting the perceptive luminance - human eye favors green color
	local luminance = (0.299*r + 0.587*g + 0.114*b)/255
	if luminance > 0.5 then
		return true -- Bright colors, black font
	else
		return false -- Dark colors, white font
	end
end

-- from norcalli's colorizer
local function create_highlight(rgb_hex, options)
	local mode = options.mode or 'background'
	rgb_hex = rgb_hex:lower()
	local cache_key = table.concat({HIGHLIGHT_MODE_NAMES[mode], rgb_hex}, "_")
	local highlight_name = HIGHLIGHT_CACHE[cache_key]
	if not highlight_name then
		if #rgb_hex == 3 then
			rgb_hex = table.concat {
				rgb_hex:sub(1,1):rep(2);
				rgb_hex:sub(2,2):rep(2);
				rgb_hex:sub(3,3):rep(2);
			}
		end
		-- Create the highlight
		highlight_name = make_highlight_name(rgb_hex, mode)
		if mode == 'foreground' then
			vim.cmd(format('highlight %s guifg=#%s', highlight_name, rgb_hex))
		else
			local r, g, b = rgb_hex:sub(1,2), rgb_hex:sub(3,4), rgb_hex:sub(5,6)
			r, g, b = tonumber(r,16), tonumber(g,16), tonumber(b,16)
			local fg_color
			if color_is_bright(r,g,b) then
				fg_color = "000000"
			else
				fg_color = "ffffff"
			end
			vim.cmd(format('highlight %s guifg=#%s guibg=#%s', highlight_name, fg_color, rgb_hex))
		end
		HIGHLIGHT_CACHE[cache_key] = highlight_name
	end
	return highlight_name
end

-- local function show_details_win()
--   local issue_bufnr = api.nvim_get_current_buf()
-- 	local bufname = api.nvim_buf_get_name(issue_bufnr)
--   if not vim.startswith(bufname, 'github://') then return end
--
--   --log.info('show details', issue_bufnr, bufname, vim.fn.bufname())
--
-- 	local labels = api.nvim_buf_get_var(issue_bufnr, 'labels')
-- 	local assignees = api.nvim_buf_get_var(issue_bufnr, 'assignees')
-- 	local milestone = api.nvim_buf_get_var(issue_bufnr, 'milestone')
--
-- 	local lines = {''}
-- 	local hls = {}
-- 	local line
-- 	local longest_line = 10
--
-- 	table.insert(lines, ' Labels:')
-- 	if labels and #labels > 0 then
-- 		for _, label in ipairs(labels) do
-- 			line = format('  -  %s ', label.name)
-- 			local highlight_name = create_highlight(label.color, {})
-- 			table.insert(lines, line)
-- 			table.insert(hls, {
-- 					['name'] = highlight_name;
-- 					['line'] = #lines-1;
-- 					['start'] = 4;
-- 					['end'] = #line;
-- 				})
-- 			longest_line = max(longest_line, #line)
-- 		end
-- 	else
-- 		line = '   None yet'
-- 		table.insert(lines, line)
-- 		longest_line = max(longest_line, #line)
-- 	end
-- 	table.insert(lines, '')
--
-- 	table.insert(lines, ' Assignees:')
-- 	if assignees and #assignees > 0 then
-- 		for _, as in ipairs(assignees) do
-- 			line = format('  - %s', as.login)
-- 			table.insert(lines, line)
-- 			longest_line = max(longest_line, #line)
-- 		end
-- 	else
-- 		line = '   No one assigned '
-- 		table.insert(lines, line)
-- 		longest_line = max(longest_line, #line)
-- 	end
-- 	table.insert(lines, '')
--
-- 	table.insert(lines, ' Milestone:')
-- 	if milestone then
-- 		line = format('  - %s (%s)', milestone.title, milestone.state)
-- 		table.insert(lines, line)
-- 		longest_line = max(longest_line, #line)
-- 	else
-- 		line = '   No milestone'
-- 		table.insert(lines, line)
-- 		longest_line = max(longest_line, #line)
-- 	end
-- 	table.insert(lines, '')
--
-- 	local bufnr = api.nvim_create_buf(true, false)
-- 	api.nvim_buf_set_lines(bufnr, 0, -1, true, lines)
-- 	highlight(bufnr, hls)
--
-- 	local current_win = api.nvim_get_current_win()
-- 	local win_width = vim.fn.winwidth(current_win)
-- 	local vertical_padding = 1
-- 	local horizontal_padding = 1
-- 	local popup_width = longest_line + 1
-- 	local popup_height = #lines
--
-- 	local win_opts = {
-- 		relative = 'win';
-- 		win = current_win;
-- 		width = popup_width;
-- 		height = popup_height;
-- 		style = 'minimal';
-- 		focusable = false;
-- 		row = vertical_padding;
-- 		col = win_width - horizontal_padding - popup_width;
-- 	}
--
-- 	local winnr = api.nvim_open_win(bufnr, false, win_opts)
-- 	api.nvim_win_set_option(winnr, "winhighlight", "NormalFloat:OctoNvimFloat,EndOfBuffer:OctoNvimFloat")
--
--   -- save the details win handle
--   api.nvim_buf_set_var(issue_bufnr, 'details_win', {
--     winnr = winnr;
--     bufnr = bufnr;
--   })
-- end

-- local function close_details_win()
--   local bufnr = api.nvim_get_current_buf()
--   local bufname = api.nvim_buf_get_name(bufnr)
--   --log.info('close_win', bufnr, bufname, vim.fn.expand('<afile>'))
--   if vim.startswith(bufname, 'github://') then
--     local details = api.nvim_buf_get_var(bufnr, 'details_win')
--     vim.cmd(string.format('%dbw!', details.bufnr))
--     --pcall(api.nvim_win_close, details.winnr, 1)
--   end
-- end

local function get_extmark_region(bufnr, mark)
	-- extmarks are placed on
	-- start line - 1 (except for line 0)
	-- end line + 2
	local start_line = mark[1] + 1
	if start_line == 1 then start_line= 0 end
	local end_line = mark[3]['end_row'] - 2
	if start_line > end_line then end_line = start_line end
	-- Indexing is zero-based, end-exclusive, so adding 1 to end line
	local lines = api.nvim_buf_get_lines(bufnr, start_line, end_line + 1, true)
	local text = vim.fn.join(lines, '\n')
	return start_line, end_line, text
end

local function update_metadata(metadata, start_line, end_line, text)
	metadata['start_line'] = start_line
	metadata['end_line'] = end_line
	if text ~= metadata['saved_body'] then
		metadata['dirty'] = true
	else
		metadata['dirty'] = false
	end
	metadata['body'] = text
end

-- definitions
octo_em_ns = api.nvim_create_namespace('octo_marks')
octo_hl_ns = api.nvim_create_namespace('octo_highlights')
octo_vt_ns = api.nvim_create_namespace('octo_virtualtexts')

vim.cmd [[ sign define clean_block_start text=┌ ]]
vim.cmd [[ sign define clean_block_end text=└ ]]
vim.cmd [[ sign define dirty_block_start text=┌ texthl=OctoNvimDirty ]]
vim.cmd [[ sign define dirty_block_end text=└ texthl=OctoNvimDirty ]]
vim.cmd [[ sign define dirty_block_middle text=│ texthl=OctoNvimDirty ]]
vim.cmd [[ sign define clean_block_middle text=│ ]]
vim.cmd [[ sign define clean_line text=[ ]]
vim.cmd [[ sign define dirty_line text=[ texthl=OctoNvimDirty ]]

local function update_issue_metadata(bufnr)

	local mark, text, start_line, end_line, metadata

	-- title
	metadata = api.nvim_buf_get_var(bufnr, 'title')
	mark = api.nvim_buf_get_extmark_by_id(bufnr, octo_em_ns, metadata.extmark, {details=true})
	start_line, end_line, text = get_extmark_region(bufnr, mark)
	update_metadata(metadata, start_line, end_line, text)
	api.nvim_buf_set_var(bufnr, 'title', metadata)

	-- description
	metadata = api.nvim_buf_get_var(bufnr, 'description')
	mark = api.nvim_buf_get_extmark_by_id(bufnr, octo_em_ns, metadata.extmark, {details=true})
	start_line, end_line, text = get_extmark_region(bufnr, mark)
	if text == '' then
		-- description has been removed
		-- the space in ' ' is crucial to prevent this block of code from repeating on TextChanged(I)?
		api.nvim_buf_set_lines(bufnr, start_line, start_line+1, false, {' ',''})
		local winnr = api.nvim_get_current_win()
		api.nvim_win_set_cursor(winnr, {start_line+1, 0})
	end
	update_metadata(metadata, start_line, end_line, text)
	api.nvim_buf_set_var(bufnr, 'description', metadata)

	-- comments
	local comments = api.nvim_buf_get_var(bufnr, 'comments')
	for i, m in ipairs(comments) do
		metadata = m
		mark = api.nvim_buf_get_extmark_by_id(bufnr, octo_em_ns, metadata.extmark, {details=true})
		start_line, end_line, text = get_extmark_region(bufnr, mark)

		if text == '' then
			-- comment has been removed
			-- the space in ' ' is crucial to prevent this block of code from repeating on TextChanged(I)?
			api.nvim_buf_set_lines(bufnr, start_line, start_line+1, false, {' ', ''})
			local winnr = api.nvim_get_current_win()
			api.nvim_win_set_cursor(winnr, {start_line+1, 0})

		end

		update_metadata(metadata, start_line, end_line, text)
		comments[i] = metadata
	end
	api.nvim_buf_set_var(bufnr, 'comments', comments)
end

local function render_signcolumn(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()
	local bufname = api.nvim_buf_get_name(bufnr)
  if not vim.startswith(bufname, 'github://') then return end

	local issue_dirty = false

	-- update comment metadata (lines, etc.)
	update_issue_metadata(bufnr)

	-- clear all signs
	sign_unplace(bufnr)

	-- clear virtual texts
	api.nvim_buf_clear_namespace(bufnr, octo_vt_ns, 0, -1)

	-- title
	local title = api.nvim_buf_get_var(bufnr, 'title')
	if title['dirty'] then issue_dirty = true end
	local start_line = title['start_line']
	local end_line = title['end_line']
	place_signs(bufnr, start_line, end_line, title['dirty'])

	-- title virtual text
	local state = api.nvim_buf_get_var(bufnr, 'state'):upper()
	local title_vt = {
		{tostring(api.nvim_buf_get_var(bufnr, 'number')), 'OctoNvimIssueId'},
		{format(' [%s]', state), 'OctoNvimIssue'..state}
	}
	api.nvim_buf_set_virtual_text(bufnr, octo_vt_ns, 0, title_vt, {})

	-- description
	local desc = api.nvim_buf_get_var(bufnr, 'description')
	if desc.dirty then issue_dirty = true end
	start_line = desc['start_line']
	end_line = desc['end_line']
	place_signs(bufnr, start_line, end_line, desc.dirty)

	-- description virtual text
	if is_blank(desc['body']) then
		local desc_vt = {{NO_BODY_MSG, 'OctoNvimEmpty'}}
		api.nvim_buf_set_virtual_text(bufnr, octo_vt_ns, start_line, desc_vt, {})
	end

	-- comments
	local comments = api.nvim_buf_get_var(bufnr, 'comments')
	for _, c in ipairs(comments) do
		if c.dirty then issue_dirty = true end
		start_line = c['start_line']
		end_line = c['end_line']
		place_signs(bufnr, start_line, end_line, c.dirty)

		-- comment virtual text
		if is_blank(c['body']) then
			local comment_vt = {{NO_BODY_MSG, 'OctoNvimEmpty'}}
			api.nvim_buf_set_virtual_text(bufnr, octo_vt_ns, start_line, comment_vt, {})
		end
	end

	-- reset modified option
	if not issue_dirty then
		api.nvim_buf_set_option(bufnr, 'modified', false)
	end
end

local function print_details(issue, content, hls)

  -- author
  local author_line = 'Created by:'
  table.insert(hls, {
    ['name'] = 'OctoNvimDetailsLabel';
    ['line'] = #content;
    ['start'] = 0;
    ['end'] = #author_line;
  })
  table.insert(hls, {
    ['name'] = 'OctoNvimDetailsValue';
    ['line'] = #content;
    ['start'] = #author_line+1;
    ['end'] = -1;
  })
  author_line = format('%s %s', author_line, issue.user.login)
	vim.list_extend(content, {author_line})

  -- created_at
  local created_at_line = 'Created at:'
  table.insert(hls, {
    ['name'] = 'OctoNvimDetailsLabel';
    ['line'] = #content;
    ['start'] = 0;
    ['end'] = #created_at_line;
  })
  table.insert(hls, {
    ['name'] = 'OctoNvimDetailsValue';
    ['line'] = #content;
    ['start'] = #created_at_line+1;
    ['end'] = -1;
  })
  created_at_line = format('%s %s', created_at_line, issue.created_at)
	vim.list_extend(content, {created_at_line})

  -- updated_at
  local updated_at_line = 'updated at:'
  table.insert(hls, {
    ['name'] = 'OctoNvimDetailsLabel';
    ['line'] = #content;
    ['start'] = 0;
    ['end'] = #updated_at_line;
  })
  table.insert(hls, {
    ['name'] = 'OctoNvimDetailsValue';
    ['line'] = #content;
    ['start'] = #updated_at_line+1;
    ['end'] = -1;
  })
  updated_at_line = format('%s %s', updated_at_line, issue.updated_at)
	vim.list_extend(content, {updated_at_line})
  
  -- closed_at
  if state == 'closed' then
    local closed_at_line = 'closed at:'
    table.insert(hls, {
      ['name'] = 'OctoNvimDetailsLabel';
      ['line'] = #content;
      ['start'] = 0;
      ['end'] = #closed_at_line;
    })
    table.insert(hls, {
      ['name'] = 'OctoNvimDetailsValue';
      ['line'] = #content;
      ['start'] = #closed_at_line+1;
      ['end'] = -1;
    })
    closed_at_line = format('%s %s', closed_at_line, issue.closed_at)
    vim.list_extend(content, {closed_at_line})
  end

  -- assignees
	local assignees_line = 'Assignees:'
  table.insert(hls, {
    ['name'] = 'OctoNvimDetailsLabel';
    ['line'] = #content;
    ['start'] = 0;
    ['end'] = #assignees_line;
  })
	if issue.assignees and #issue.assignees > 0 then
		for _, as in ipairs(issue.assignees) do
			table.insert(hls, {
        ['name'] = 'OctoNvimDetailsValue';
        ['line'] = #content;
        ['start'] = #assignees_line+1;
        ['end'] = #assignees_line + #as.login + 1;
      })
			assignees_line = format('%s %s ,', assignees_line, as.login)
		end
	else
		assignees_line = assignees_line..' No one assigned '
	end
  if vim.endswith(assignees_line, ',') then
    assignees_line = assignees_line:sub(1, -2)
  end
	vim.list_extend(content, {assignees_line})

  -- requested reviewers
  if issue.pull_request then
    local req_opts = deepcopy(curl_opts)
    req_opts.sync = true
    local response, status = curl.request(issue.pull_request.url, req_opts)
		local resp = json.parse(response)
		if check_error(status, resp) then return end
    local requested_reviewers_line = 'Requested reviewers:'
    table.insert(hls, {
      ['name'] = 'OctoNvimDetailsLabel';
      ['line'] = #content;
      ['start'] = 0;
      ['end'] = #requested_reviewers_line;
    })
    if resp.requested_reviewers and #resp.requested_reviewers > 0 then
      for _, as in ipairs(resp.requested_reviewers) do
        table.insert(hls, {
          ['name'] = 'OctoNvimDetailsValue';
          ['line'] = #content;
          ['start'] = #requested_reviewers_line+1;
          ['end'] = #requested_reviewers_line + #as.login + 1;
        })
        requested_reviewers_line = format('%s %s ,', requested_reviewers_line, as.login)
      end
    else
      requested_reviewers_line = requested_reviewers_line..' No reviews'
    end
    if vim.endswith(requested_reviewers_line, ',') then
      requested_reviewers_line = requested_reviewers_line:sub(1, -2)
    end
    vim.list_extend(content, {requested_reviewers_line})
  end

  -- reviews
  if issue.pull_request then
    local req_opts = deepcopy(curl_opts)
    req_opts.sync = true
    local response, status = curl.request(issue.pull_request.url..'/reviews', req_opts)
		local resp = json.parse(response)
		if check_error(status, resp) then return end
    local reviewers_line = 'Reviews:'
    table.insert(hls, {
      ['name'] = 'OctoNvimDetailsLabel';
      ['line'] = #content;
      ['start'] = 0;
      ['end'] = #reviewers_line;
    })
    if resp and #resp > 0 then
      for _, as in ipairs(resp) do
        table.insert(hls, {
          ['name'] = 'OctoNvimDetailsValue';
          ['line'] = #content;
          ['start'] = #reviewers_line+1;
          ['end'] = #reviewers_line + #as.user.login + #as.state + 4;
        })
        reviewers_line = format('%s %s (%s),', reviewers_line, as.user.login, as.state)
      end
    else
      reviewers_line = reviewers_line..' No reviews'
    end
    if vim.endswith(reviewers_line, ',') then
      reviewers_line = reviewers_line:sub(1, -2)
    end
    vim.list_extend(content, {reviewers_line})
  end

  -- milestones
  local milestone_line = 'Milestone:'
  local ms = issue.milestone
  table.insert(hls, {
    ['name'] = 'OctoNvimDetailsLabel';
    ['line'] = #content;
    ['start'] = 0;
    ['end'] = #milestone_line;
  })
	if ms ~= nil and ms ~= vim.NIL then
    table.insert(hls, {
      ['name'] = 'OctoNvimDetailsValue';
      ['line'] = #content;
      ['start'] = #milestone_line+1;
      ['end'] = -1;
    })
    milestone_line = format('%s %s (%s)', milestone_line, ms.title, ms.state)
	else
		milestone_line = milestone_line..' No milestone'
	end
	vim.list_extend(content, {milestone_line})

  -- labels
  local labels_line = 'Labels:'
  table.insert(hls, {
    ['name'] = 'OctoNvimDetailsLabel';
    ['line'] = #content;
    ['start'] = 0;
    ['end'] = #labels_line;
  })
	if issue.labels and #issue.labels > 0 then
		for _, label in ipairs(issue.labels) do
			table.insert(hls, {
        ['name'] = create_highlight(label.color, {});
        ['line'] = #content;
        ['start'] = #labels_line+1;
        ['end'] = #labels_line + #label.name + 1;
      })
			labels_line = format('%s %s', labels_line, label.name)
		end
	else
    labels_line = labels_line..' None yet'
	end
	vim.list_extend(content, {labels_line, '', ''})

end

local function create_issue_buffer(issue, repo)

	if not issue['id'] then
		api.nvim_err_writeln(format('Cannot find issue in %s', repo))
		return
	end

	local iid = issue['id']
	local title = issue['title']
	local body = string.gsub(issue['body'], '\r\n', '\n')
	local number = issue['number']
	local state = issue['state']
	local comments_url = issue['comments_url']..'?per_page=100'
	local content = {}
	local hls = {}
	local extmarks = {}

  -- close detail window
  --close_details_win()

	-- create buffer
	local bufnr = api.nvim_get_current_buf()

	-- delete extmarks
	for _, m in ipairs(api.nvim_buf_get_extmarks(bufnr, octo_em_ns, 0, -1, {})) do
		api.nvim_buf_del_extmark(bufnr, octo_em_ns, m[1])
	end

	local function render_buffer(bufnr)
		-- render buffer
		api.nvim_buf_set_lines(bufnr, 0, -1, false, content)
		api.nvim_buf_set_lines(bufnr, -2, -1, false, {})

		-- add highlights
		table.insert(hls, {name = 'OctoNvimIssueTitle', line = 0, start = 0, ['end'] = -1 })
		highlight(bufnr, hls)

		-- set extmarks
		local extmarks_ids = {}
		for _, m in ipairs(extmarks) do
			-- (empty line) start ext mark at 0
			-- start line
			-- ...
			-- end line
			-- (empty line)
			-- (empty line) end ext mark at 0

			-- except for title where we cant place initial mark on line -1

			local start_line = m[1]
			local end_line = m[2]
			local m_id = api.nvim_buf_set_extmark(bufnr, octo_em_ns, max(0,start_line-1), 0, {
					end_line=end_line+2;
					end_col=0;
				})
			table.insert(extmarks_ids, m_id)
		end
		local title_metadata = api.nvim_buf_get_var(bufnr, 'title')
		title_metadata['extmark'] = extmarks_ids[1]
		api.nvim_buf_set_var(bufnr, 'title', title_metadata)

		local desc_metadata = api.nvim_buf_get_var(bufnr, 'description')
		desc_metadata['extmark'] = extmarks_ids[2]
		api.nvim_buf_set_var(bufnr, 'description', desc_metadata)

		local comments_metadata = api.nvim_buf_get_var(bufnr, 'comments')
		for i=3,#extmarks_ids,1 do
			comments_metadata[i-2]['extmark'] = extmarks_ids[i]
		end
		api.nvim_buf_set_var(bufnr, 'comments', comments_metadata)

		-- drop undo history
		vim.fn['octo#clear_history']()

		-- show signs
		render_signcolumn(bufnr)

		-- reset modified option
		api.nvim_buf_set_option(bufnr, 'modified', false)

		-- show details window
		-- show_details_win()
	end

	local function write(text)
		local lines = vim.split(text, '\n', true)
		local start_line = #content + 1
		vim.list_extend(content, lines)
		local end_line = #content
		-- make them 0-index based
		table.insert(extmarks, {start_line-1, end_line-1})
	end

	local function write_comments(response, status)
		local resp = json.parse(response)
		if check_error(status, resp) then return end
		local comments_metadata = api.nvim_buf_get_var(bufnr, 'comments')
		for _, c in ipairs(resp) do

			-- heading
			local heading = format('On %s %s commented:', c.created_at, c.user.login)
			table.insert(hls, {
					['name'] = 'OctoNvimCommentHeading';
					['line'] = #content;
					['start'] = 0;
					['end'] = #format('On %s ', c.created_at);
				})
			table.insert(hls, {
					['name'] = 'OctoNvimCommentUser';
					['line'] = #content;
					['start'] = #format('On %s ', c.created_at);
					['end'] = #format('On %s %s', c.created_at, c.user.login);
				})
			table.insert(hls, {
					['name'] = 'OctoNvimCommentHeading';
					['line'] = #content;
					['start'] = #format('On %s %s ', c.created_at, c.user.login);
					['end'] = -1;
				})

			vim.list_extend(content, {heading, ''})

			-- body
			local cbody = string.gsub(c['body'], '\r\n', '\n')
			if vim.startswith(cbody, NO_BODY_MSG) then cbody = ' ' end
			write(cbody)
			vim.list_extend(content, {'', '', ''})
			local comment = {
				id = c['id'];
				dirty = false;
				saved_body = cbody;
				body = cbody;
			}
			table.insert(comments_metadata, comment)
		end
		api.nvim_buf_set_var(bufnr, 'comments', comments_metadata)

		render_buffer(bufnr)
	end

	-- configure buffer
	api.nvim_buf_set_option(bufnr, 'filetype', 'octo_issue')
	api.nvim_buf_set_option(bufnr, 'buftype', 'acwrite')

	-- register issue
	api.nvim_buf_set_var(bufnr, 'iid', iid)
	api.nvim_buf_set_var(bufnr, 'number', number)
	api.nvim_buf_set_var(bufnr, 'repo', repo)
	api.nvim_buf_set_var(bufnr, 'state', state)
	api.nvim_buf_set_var(bufnr, 'labels', issue.labels)
	api.nvim_buf_set_var(bufnr, 'assignees', issue.assignees)
	api.nvim_buf_set_var(bufnr, 'milestone', issue.milestone)

	-- write title
	write(title)
	vim.list_extend(content, {''})
	local title_metadata = {
		saved_body = title;
		body = title;
		dirty = false
	}
	api.nvim_buf_set_var(bufnr, 'title', title_metadata)

  if true then
    -- print details in buffer
    print_details(issue, content, hls)
  end

	-- write description
	write(body)
	vim.list_extend(content, {'','',''})
	local desc_metadata = {
		saved_body = body,
		body = body,
		dirty = false
	}
	api.nvim_buf_set_var(bufnr, 'description', desc_metadata)

	-- request issue comments
  local req_opts = deepcopy(curl_opts)
	api.nvim_buf_set_var(bufnr, 'comments', {})
	if tonumber(issue['comments']) > 0 then
		curl.request(comments_url, req_opts, write_comments)
	else
		render_buffer(bufnr)
	end

	return bufnr
end

local function process_link_header(headers)
	local h = headers['Link']
	local page_count = 0
	local per_page = 0
	if nil ~= h then
		for n in string.gmatch(h, '&page=(%d+)') do
			page_count = max(page_count, n)
		end
		for p in string.gmatch(h, '&per_page=(%d+)') do
			per_page = max(per_page, p)
		end
		return per_page, page_count*per_page
	else
		return nil, nil
	end
end

local function get_url(url, params)
	url = url .. '?foo=bar'
	for k, v in pairs(params) do
		url = format('%s\\&%s=%s', url, k, v)
	end
	return url
end

local function get_repo_issues(repo, query_params)

	query_params = query_params or {}

	--log.info('getting issues for repo', repo)

	query_params = {
		state = query_params.state or 'open';
		per_page = query_params.per_page or 50;
		filter = query_params.filter;
		labels = query_params.labels;
		since = query_params.since
	}

	local issues_url = get_url(format('https://api.github.com/repos/%s/issues', repo), query_params)
	local req_opts = deepcopy(curl_opts)
	req_opts.sync = true
	local body, _, headers = curl.request(issues_url, req_opts)
	local count, total = process_link_header(headers)
	local issues = json.parse(body)

  -- TODO: filter out pull_requests (NOT WORKING)
  vim.tbl_filter(function(e)
    return e.pull_request == nil
  end, issues)

	if count == nil and total == nil then
		count = #issues
		total = #issues
	end
	return {
		issues = issues;
		count = count;
		total = total;
	}
end

local function load_issue()
  local bufname = vim.fn.bufname()
  local repo, number = string.match(bufname, 'github://(.+)/(%d+)')
  if not repo or not number then
		api.nvim_err_writeln('Incorrect github url: '..bufname)
    return
  end
	local url = format('https://api.github.com/repos/%s/issues/%s', repo, number)

	local function load_cb(response, status)
		local issue = json.parse(response)
		if check_error(status, issue) then return end
		create_issue_buffer(issue, repo)
	end
	local url_opts = deepcopy(curl_opts)
	curl.request(url, url_opts, load_cb)
end

local function get_issue(repo, number)
  vim.cmd(format('edit github://%s/%s', repo, number))
end

local function save_issue(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()
	local bufname = api.nvim_buf_get_name(bufnr)
  if not vim.startswith(bufname, 'github://') then return end

  -- number
	local number = api.nvim_buf_get_var(bufnr, 'number')

	-- repo
	local repo = api.nvim_buf_get_var(bufnr, 'repo')
	if not repo then
		api.nvim_err_writeln('Buffer is not linked to a GitHub issue')
		return
	end

	--log.info('Saving issue:', number, 'repo:', repo, 'bufnr:', bufnr)

	-- collect comment metadata
	update_issue_metadata(bufnr)

	-- title & description
	local title_metadata = api.nvim_buf_get_var(bufnr, 'title')
	local desc_metadata = api.nvim_buf_get_var(bufnr, 'description')
	if title_metadata.dirty or desc_metadata.dirty then

		-- trust but validate
		if string.find(title_metadata['body'], '\n') then
			api.nvim_err_writeln("Title can't contains new lines")
			return
		elseif title_metadata['body'] == '' then
			api.nvim_err_writeln("Title can't be blank")
			return
		end

		local update_url = format('https://api.github.com/repos/%s/issues/%s', repo, number)
		local function update_cb(response, status)
			local resp = json.parse(response)
			if check_error(status, resp) then return end

			if title_metadata['body'] == resp['title'] then
				title_metadata['saved_body'] = resp['title']
				title_metadata['dirty'] = false
				api.nvim_buf_set_var(bufnr, 'title', title_metadata)
			end

			if desc_metadata['body'] == resp['body'] then
				desc_metadata['saved_body'] = resp['body']
				desc_metadata['dirty'] = false
				api.nvim_buf_set_var(bufnr, 'description', desc_metadata)
			end

			render_signcolumn(bufnr)
			print('Saved!')
		end
		local update_opts = deepcopy(curl_opts)
		update_opts['body'] = json.stringify({
				title = title_metadata['body'];
				body = desc_metadata['body'];
			})
		update_opts['method'] = 'PATCH'
		curl.request(update_url, update_opts, update_cb)
	end

	-- comments
	local comments = api.nvim_buf_get_var(bufnr, 'comments')
	for _, metadata in ipairs(comments) do
		if is_blank(metadata['body']) then
			-- remove issue?
			local choice = vim.fn.confirm("Comment body can't be blank, remove comment?", "&Yes\n&No\n&Cancel", 2)
			if choice == 1 then
				local cid = metadata['id']
				local remove_url = format('https://api.github.com/repos/%s/issues/comments/%s', repo, cid)
				local function remove_comment(_)
					get_issue(repo, api.nvim_buf_get_var(bufnr, 'number'))
				end
				local remove_opts = deepcopy(curl_opts)
				remove_opts['method'] = 'DELETE'
				curl.request(remove_url, remove_opts, remove_comment)
			end
		elseif metadata['body'] ~= metadata['saved_body'] then
			local cid = metadata['id']
			local update_url = format('https://api.github.com/repos/%s/issues/comments/%s', repo, cid)

			local function update_comment(response, status)
				local resp = json.parse(response)
				if check_error(status, resp) then return end
				if metadata['body'] == resp['body'] then
					for i, c in ipairs(comments) do
						if c['id'] == resp['id'] then
							comments[i]['saved_body'] = resp['body']
							comments[i]['dirty'] = false
							break
						end
					end
					api.nvim_buf_set_var(bufnr, 'comments', comments)
					render_signcolumn(bufnr)
					print('Saved!')
				end
			end
			local update_opts = deepcopy(curl_opts)
			update_opts['body'] = json.stringify({
					body = metadata['body']
				})
			update_opts['method'] = 'PATCH'
			curl.request(update_url, update_opts, update_comment)
		end
	end

	-- reset modified option
	api.nvim_buf_set_option(bufnr, 'modified', false)
end

local function new_comment()

	local bufnr = api.nvim_get_current_buf()

	local iid = api.nvim_buf_get_var(bufnr, 'iid')
	local number = api.nvim_buf_get_var(bufnr, 'number')
	local repo = api.nvim_buf_get_var(bufnr, 'repo')

	if not iid or not number or not repo then
		api.nvim_err_writeln('Buffer is not linked to a GitHub issue')
		return
	end

	local url = format('https://api.github.com/repos/%s/issues/%s/comments', repo, number)

	local function new_comment_cb(response, status)
		local resp = json.parse(response)
		if check_error(status, resp) then return end
		if nil ~= resp['issue_url'] then
			get_issue(repo, number)
		end
	end

	local url_opts = deepcopy(curl_opts)
	url_opts['body'] = json.stringify({
			body = NO_BODY_MSG
		})
	url_opts['method'] = 'POST'
	curl.request(url, url_opts, new_comment_cb)
end

local function new_issue(repo)

	local url = format('https://api.github.com/repos/%s/issues', repo)

	local function new_issue_cb(response, status)
		local issue = json.parse(response)
		if check_error(status, issue) then return end
		create_issue_buffer(issue, repo)
	end
	local url_opts = deepcopy(curl_opts)
	url_opts['body'] = json.stringify({
			title = 'new issue';
			body = NO_BODY_MSG
		})
	url_opts['method'] = 'POST'
	curl.request(url, url_opts, new_issue_cb)
end

local function change_issue_state(state)
	local bufnr = api.nvim_get_current_buf()

	local number = api.nvim_buf_get_var(bufnr, 'number')
	local repo = api.nvim_buf_get_var(bufnr, 'repo')

	if not state then
		api.nvim_err_writeln('Missing argument: state')
		return
	end

	if not number or not repo then
		api.nvim_err_writeln('Buffer is not linked to a GitHub issues')
		return
	end

	local update_url = format('https://api.github.com/repos/%s/issues/%s', repo, number)
	local function update_state(response, status)
		local resp = json.parse(response)
		if check_error(status, resp) then return end
		if state == resp['state'] then
			api.nvim_buf_set_var(bufnr, 'state', resp['state'])
			print('Issue state changed to: '..resp['state'])
			get_issue(repo, resp['number'])
		end
	end
	local update_opts = deepcopy(curl_opts)
	update_opts['body'] = json.stringify({
			state = state;
		})
	update_opts['method'] = 'PATCH'
	curl.request(update_url, update_opts, update_state)
end

local function issue_complete(findstart, base)
	-- :he complete-functions
	if findstart == 1 then
		-- findstart
		local line = api.nvim_get_current_line()
		local pos = vim.fn.col('.')
		local i, j = 0
		while true do
			i, j = string.find(line, '#(%d*)', i+1)
			if i == nil then break end
			if pos > i and pos <= j+1 then
				return i
			end
		end
		return -2
	elseif findstart == 0 then
		local repo = api.nvim_buf_get_var(0, 'repo')
		local resp = get_repo_issues(repo)
		local entries = {}
		for _,i in ipairs(resp.issues) do
			if vim.startswith(tostring(i.number), base) then
				table.insert(entries, {
						word = tostring(i.number);
						abbr = format("#%d", i.number);
						menu = i.title;
					})
			end
		end
		return entries
	end
end

local function is_cursor_in_pattern(pattern)
	local pos = vim.fn.col('.')
	local line = api.nvim_get_current_line()
	local i, j = 0
	while true do
		local res = {string.find(line, pattern, i+1)}
    i = table.remove(res, 1)
    j = table.remove(res, 1)
		if i == nil then break end
		if pos > i and pos <= j+1 then
			return res
		end
	end
  return nil
end

local function go_to_issue()
  local res = is_cursor_in_pattern('%s#(%d*)')
  if res and #res == 1 then
    local repo = api.nvim_buf_get_var(0, 'repo')
    local number = res[1]
    get_issue(repo, number)
    return
  else
    res = is_cursor_in_pattern('https://github.com/([^/]+)/([^/]+)/([^/]+)/(%d+).*')
    if res and #res == 4 then
      local repo = string.format('%s/%s', res[1], res[2])
      local number = res[4]
      get_issue(repo, number)
      return
    end
  end
end

local function issue_action(action, kind, value)
  if action ~= 'add' and action ~= 'remove' then
    api.nvim_err_writeln('Incorrect action')
    return
  end
  if kind ~= 'assignees' and kind ~= 'labels' and kind ~= 'requested_reviewers' then
    api.nvim_err_writeln('Incorrect action kind')
    return
  end
  if vim.bo.ft ~= 'octo_issue' then
    api.nvim_err_writeln('Not in issue buffer')
    return
  end
  local number = api.nvim_buf_get_var(0, 'number')
  local repo = api.nvim_buf_get_var(0, 'repo')
  if not number or not repo then
    api.nvim_err_writeln('Missing issue metadata')
    return
  end

  local type = 'issues'
  if kind == 'requested_reviewers' then type = 'pulls' end
	local url = format('https://api.github.com/repos/%s/%s/%d/%s', repo, type, number, kind)

	local function cb(_, _)
		get_issue(repo, number)
	end
	local url_opts = deepcopy(curl_opts)
  if kind == 'assignees' then
    url_opts['body'] = json.stringify({ assignees = {value}; })
  elseif kind == 'requested_reviewers' then
    url_opts['body'] = json.stringify({ reviewers = {value}; })
  elseif kind == 'labels' and action == 'add' then
    url_opts['body'] = json.stringify({ labels = {value}; })
  elseif kind == 'labels' and action == 'remove' then
    url = format('%s/%s', url, value)
  end
  if action == 'add' then
	  url_opts['method'] = 'POST'
  elseif action == 'remove' then
	  url_opts['method'] = 'DELETE'
  end
	curl.request(url, url_opts, cb)
end

return {
	change_issue_state = change_issue_state;
	get_issue = get_issue;
	load_issue = load_issue;
	new_issue = new_issue;
	save_issue = save_issue;
	render_signcolumn = render_signcolumn;
	new_comment = new_comment;
	get_repo_issues = get_repo_issues;
	issue_complete = issue_complete;
	go_to_issue = go_to_issue;
  issue_action = issue_action;
	--show_details_win = show_details_win;
  --close_details_win = close_details_win;
}
