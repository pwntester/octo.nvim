local gh = require('octo.gh')
local vim = vim
local api = vim.api
local max = math.max
local format = string.format
local Job = require('plenary.job')
local json = {
	parse = vim.fn.json_decode;
	stringify = vim.fn.json_encode;
}

-- constants
local OCTO_EM_NS = api.nvim_create_namespace('octo_marks')
local OCTO_VT_NS = api.nvim_create_namespace('octo_virtualtexts')
local NO_BODY_MSG = 'No description provided.'
local HIGHLIGHT_NAME_PREFIX = "octo"
local HIGHLIGHT_CACHE = {}
local HIGHLIGHT_MODE_NAMES = {
	background = "mb";
	foreground = "mf";
}

-- sign definitions
vim.cmd [[ sign define clean_block_start text=┌ ]]
vim.cmd [[ sign define clean_block_end text=└ ]]
vim.cmd [[ sign define dirty_block_start text=┌ texthl=OctoNvimDirty ]]
vim.cmd [[ sign define dirty_block_end text=└ texthl=OctoNvimDirty ]]
vim.cmd [[ sign define dirty_block_middle text=│ texthl=OctoNvimDirty ]]
vim.cmd [[ sign define clean_block_middle text=│ ]]
vim.cmd [[ sign define clean_line text=[ ]]
vim.cmd [[ sign define dirty_line text=[ texthl=OctoNvimDirty ]]

-- autocommands
vim.cmd [[ augroup octo_autocmds ]]
vim.cmd [[ autocmd!]]
vim.cmd [[ au BufReadCmd github://* lua require"octo".load_issue() ]]
vim.cmd [[ au BufWriteCmd github://* lua require"octo".save_issue() ]]
vim.cmd [[ augroup END ]]

local function get_remote_name(remote)
  remote = remote or 'origin'
	local cmd = format('git config --get remote.%s.url', remote)
  local url = string.gsub(vim.fn.system(cmd), '%s+', '')
	local owner, repo
  if #vim.split(url, '://') == 2 then
    owner = vim.split(url, '/')[#vim.split(url, '/')-1]
    repo = string.gsub(vim.split(url, '/')[#vim.split(url, '/')], '.git$', '')
  elseif #vim.split(url, '@') == 2 then
    local segment = vim.split(url, ':')[2]
    owner = vim.split(segment, '/')[1]
    repo = string.gsub(vim.split(segment, '/')[2], '.git$', '')
	end
	return format('%s/%s', owner, repo)
end

local function is_blank(s)
	return not(s ~= nil and s:match("%S") ~= nil)
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

-- from https://github.com/norcalli/nvim-colorizer.lua
local function make_highlight_name(rgb, mode)
	return table.concat({HIGHLIGHT_NAME_PREFIX, HIGHLIGHT_MODE_NAMES[mode], rgb}, '_')
end

-- from https://github.com/norcalli/nvim-colorizer.lua
local function color_is_bright(r, g, b)
	-- Counting the perceptive luminance - human eye favors green color
	local luminance = (0.299*r + 0.587*g + 0.114*b)/255
	if luminance > 0.5 then
		return true -- Bright colors, black font
	else
		return false -- Dark colors, white font
	end
end

-- from https://github.com/norcalli/nvim-colorizer.lua
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
	if vim.fn.trim(text) ~= vim.fn.trim(metadata['saved_body']) then
		metadata['dirty'] = true
	else
		metadata['dirty'] = false
	end
	metadata['body'] = text
end

local function update_issue_metadata(bufnr)

	local mark, text, start_line, end_line, metadata

	-- title
	metadata = api.nvim_buf_get_var(bufnr, 'title')
	mark = api.nvim_buf_get_extmark_by_id(bufnr, OCTO_EM_NS, metadata.extmark, {details=true})
	start_line, end_line, text = get_extmark_region(bufnr, mark)
	update_metadata(metadata, start_line, end_line, text)
	api.nvim_buf_set_var(bufnr, 'title', metadata)

	-- description
	metadata = api.nvim_buf_get_var(bufnr, 'description')
	mark = api.nvim_buf_get_extmark_by_id(bufnr, OCTO_EM_NS, metadata.extmark, {details=true})
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
		mark = api.nvim_buf_get_extmark_by_id(bufnr, OCTO_EM_NS, metadata.extmark, {details=true})
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
	--api.nvim_buf_clear_namespace(bufnr, OCTO_VT_NS, 0, -1)

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
	api.nvim_buf_set_virtual_text(bufnr, OCTO_VT_NS, 0, title_vt, {})

	-- description
	local desc = api.nvim_buf_get_var(bufnr, 'description')
	if desc.dirty then issue_dirty = true end
	start_line = desc['start_line']
	end_line = desc['end_line']
	place_signs(bufnr, start_line, end_line, desc.dirty)

	-- description virtual text
	if is_blank(desc['body']) then
		local desc_vt = {{NO_BODY_MSG, 'OctoNvimEmpty'}}
		api.nvim_buf_set_virtual_text(bufnr, OCTO_VT_NS, start_line, desc_vt, {})
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
			api.nvim_buf_set_virtual_text(bufnr, OCTO_VT_NS, start_line, comment_vt, {})
		end
	end

	-- reset modified option
	if not issue_dirty then
		api.nvim_buf_set_option(bufnr, 'modified', false)
	end
end

local function write_block(lines, opts)
  local bufnr = opts.bufnr or api.nvim_get_current_buf()
  if type(lines) == 'string' then
    lines = vim.split(lines, '\n', true)
  end
  local start_line = api.nvim_buf_line_count(bufnr) + 1

  -- write content lines
  if start_line == 2 and vim.fn.getline('.') == '' then
    api.nvim_buf_set_lines(bufnr, 0, 0, false, lines)
  else
    api.nvim_buf_set_lines(bufnr, -1, -1, false, lines)
  end

  -- trailing empty lines
  if opts.trailing_lines then
    for _=1, opts.trailing_lines, 1 do
      api.nvim_buf_set_lines(bufnr, -1, -1, false, {''})
    end
  end

  -- remove last line when writing at the beggining of the buffer
  if start_line == 2 then
    --api.nvim_buf_set_lines(bufnr, -2, -1, false, {})
    start_line = 1
  end

  -- set extmarks
  local end_line = start_line
  local count = api.nvim_buf_line_count(bufnr)
  for i=count, start_line, -1 do
    local line = vim.fn.getline(i) or ''
    if '' ~= line then
      end_line = i
      break
    end
  end

  if opts.mark then

    -- (empty line) start ext mark at 0
    -- start line
    -- ...
    -- end line
    -- (empty line)
    -- (empty line) end ext mark at 0

    -- except for title where we cant place initial mark on line -1
    return api.nvim_buf_set_extmark(bufnr,
      OCTO_EM_NS,
      max(0,start_line-2),
      0,
      { end_line=end_line+1; end_col=0; }
    )
  end
end

local function write_details(bufnr, issue)

  local hls = {}
  local content = {}

  -- author
	write_block({''}, {bufnr=bufnr; mark=false;})
	local author_vt = {
		{'Created by: ', 'OctoNvimDetailsLabel'},
		{issue.user.login, 'OctoNvimDetailsValue'},
	}
	api.nvim_buf_set_virtual_text(bufnr, OCTO_VT_NS, api.nvim_buf_line_count(bufnr) - 1, author_vt, {})

  -- created_at
	write_block({''}, {bufnr=bufnr; mark=false;})
	local created_at_vt = {
		{'Created at: ', 'OctoNvimDetailsLabel'},
		{issue.created_at, 'OctoNvimDetailsValue'},
	}
	api.nvim_buf_set_virtual_text(bufnr, OCTO_VT_NS, api.nvim_buf_line_count(bufnr) - 1, created_at_vt, {})

  -- updated_at
	write_block({''}, {bufnr=bufnr; mark=false;})
	local updated_at_vt = {
		{'Updated at: ', 'OctoNvimDetailsLabel'},
		{issue.updated_at, 'OctoNvimDetailsValue'},
	}
	api.nvim_buf_set_virtual_text(bufnr, OCTO_VT_NS, api.nvim_buf_line_count(bufnr) - 1, updated_at_vt, {})

  -- closed_at
  if issue.state == 'closed' then
    write_block({''}, {bufnr=bufnr; mark=false;})
    local closed_at_vt = {
      {'Closed at: ', 'OctoNvimDetailsLabel'},
      {issue.closed_at, 'OctoNvimDetailsValue'},
    }
    api.nvim_buf_set_virtual_text(bufnr, OCTO_VT_NS, api.nvim_buf_line_count(bufnr) - 1, closed_at_vt, {})
  end

  -- assignees
	write_block({''}, {bufnr=bufnr; mark=false;})
	local assignees_vt = {
		{'Assignees: ', 'OctoNvimDetailsLabel'},
	}
	if issue.assignees and #issue.assignees > 0 then
		for i, as in ipairs(issue.assignees) do
			table.insert(assignees_vt, {as.login, 'OctoNvimDetailsValue'})
      if i ~= #issue.assignees then
			  table.insert(assignees_vt, {', ', 'OctoNvimDetailsLabel'})
      end
		end
	else
    table.insert(assignees_vt, {
		  'No one assigned '
    })
	end
	api.nvim_buf_set_virtual_text(bufnr, OCTO_VT_NS, api.nvim_buf_line_count(bufnr) - 1, assignees_vt, {})

  if issue.pull_request then
    local url = issue.pull_request.url
    local segments = vim.split(url, '/')
    local owner = segments[5]
    local repo = segments[6]
    local pr_id = segments[8]
    local response = gh.run({
      args = {'api', format('repos/%s/%s/pulls/%d', owner, repo, pr_id)};
      mode = 'sync';
    })
		local resp = json.parse(response)

    -- requested reviewers
    write_block({''}, {bufnr=bufnr; mark=false;})
    local requested_reviewers_vt = {
      {'Requested Reviewers: ', 'OctoNvimDetailsLabel'},
    }
    if resp.requested_reviewers and #resp.requested_reviewers > 0 then
      for i, as in ipairs(resp.requested_reviewers) do
        table.insert(requested_reviewers_vt, {as.login, 'OctoNvimDetailsValue'})
        if i ~= #issue.assignees then
          table.insert(requested_reviewers_vt, {', ', 'OctoNvimDetailsLabel'})
        end
      end
    else
      table.insert(requested_reviewers_vt, {
        'No requested reviewers'
      })
    end
    api.nvim_buf_set_virtual_text(bufnr, OCTO_VT_NS, api.nvim_buf_line_count(bufnr) - 1, requested_reviewers_vt, {})

    -- reviews
    write_block({''}, {bufnr=bufnr; mark=false;})
    local reviewers_vt = {
      {'Reviews: ', 'OctoNvimDetailsLabel'},
    }
    if resp and #resp > 0 then
      for i, as in ipairs(resp) do
        table.insert(reviewers_vt, {format('%s (%s)', as.user.login, as.state), 'OctoNvimDetailsValue'})
        if i ~= #issue.assignees then
          table.insert(reviewers_vt, {', ', 'OctoNvimDetailsLabel'})
        end
      end
    else
      table.insert(reviewers_vt, {
        'No reviewers'
      })
    end
    api.nvim_buf_set_virtual_text(bufnr, OCTO_VT_NS, api.nvim_buf_line_count(bufnr) - 1, assignees_vt, {})
  end

  -- milestones
  write_block({''}, {bufnr=bufnr; mark=false;})
  local ms = issue.milestone
  local milestone_vt = {
    {'Milestone: ', 'OctoNvimDetailsLabel'},
  }
	if ms ~= nil and ms ~= vim.NIL then
    table.insert(milestone_vt, {format('%s (%s)', ms.title, ms.state), 'OctoNvimDetailsValue'})
	else
    table.insert(milestone_vt, {'No milestone', 'OctoNvimDetailsValue'})
	end
  api.nvim_buf_set_virtual_text(bufnr, OCTO_VT_NS, api.nvim_buf_line_count(bufnr) - 1, milestone_vt, {})

  -- labels
  write_block({''}, {bufnr=bufnr; mark=false;})
  local labels_vt = {
    {'Labels: ', 'OctoNvimDetailsLabel'},
  }
	if issue.labels and #issue.labels > 0 then
		for _, label in ipairs(issue.labels) do
      table.insert(labels_vt, {'', create_highlight(label.color, {mode='foreground'})})
      table.insert(labels_vt, {label.name, create_highlight(label.color, {})})
      table.insert(labels_vt, {'', create_highlight(label.color, {mode='foreground'})})
      table.insert(labels_vt, {' ', 'OctoNvimDetailsLabel'})
		end
	else
    table.insert(labels_vt, {'None yet', 'OctoNvimDetailsValue'})
	end
  api.nvim_buf_set_virtual_text(bufnr, OCTO_VT_NS, api.nvim_buf_line_count(bufnr) - 1, labels_vt, {})

  write_block({''}, {bufnr=bufnr; mark=false;})
end

local function write_comment(bufnr, comment)

  -- heading
	write_block({'', ''}, {bufnr=bufnr; mark=false;})
	local header_vt = {
		{format('On %s ', comment.created_at), 'OctoNvimCommentHeading'},
		{comment.user.login, 'OctoNvimCommentUser'},
		{' commented', 'OctoNvimCommentHeading'}
	}
	api.nvim_buf_set_virtual_text(bufnr, OCTO_VT_NS, api.nvim_buf_line_count(bufnr) - 2, header_vt, {})

  -- body
  local content = {}
  local comment_body = string.gsub(comment['body'], '\r\n', '\n')
  if vim.startswith(comment_body, NO_BODY_MSG) then comment_body = ' ' end
  vim.list_extend(content, vim.split(comment_body, '\n', true))
  vim.list_extend(content, {'', '', ''})
	local comment_mark = write_block(content, {bufnr=bufnr; mark=true;})

  -- reactions
  if comment.reactions.total_count > 0 then
    local reactions_vt = {}
    for reaction, count in pairs(comment.reactions) do
      local emoji = require'octo.util'.reaction_map[reaction]
      if emoji and count > 0 then
        table.insert(reactions_vt, {'', 'OctoNvimBubble1'})
        table.insert(reactions_vt, {emoji, 'OctoNvimBubble2'})
        table.insert(reactions_vt, {'', 'OctoNvimBubble1'})
        table.insert(reactions_vt, {format(' %s ', count), 'Normal'})
      end
    end
	  api.nvim_buf_set_virtual_text(bufnr, OCTO_VT_NS, api.nvim_buf_line_count(bufnr) - 2, reactions_vt, {})
  end

  -- update metadata
  local comments_metadata = api.nvim_buf_get_var(bufnr, 'comments')
  table.insert(comments_metadata, {
    id = comment['id'];
    dirty = false;
    saved_body = comment_body;
    body = comment_body;
    extmark = comment_mark;
  })
  api.nvim_buf_set_var(bufnr, 'comments', comments_metadata)
end

local function create_issue_buffer(issue, repo)

	if not issue['id'] then
		api.nvim_err_writeln(format('Cannot find issue in %s', repo))
		return
	end

	local iid = issue['id']
	local title = issue['title']
	local description = string.gsub(issue['body'], '\r\n', '\n')
	local number = issue['number']
	local state = issue['state']

	-- create buffer
	local bufnr = api.nvim_get_current_buf()

	-- delete extmarks
	for _, m in ipairs(api.nvim_buf_get_extmarks(bufnr, OCTO_EM_NS, 0, -1, {})) do
		api.nvim_buf_del_extmark(bufnr, OCTO_EM_NS, m[1])
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
  local title_hls = {name = 'OctoNvimIssueTitle', line = 0, start = 0, ['end'] = -1 }
	local title_mark = write_block(title, {bufnr=bufnr; mark=true; trailing_lines=1; highlights=title_hls})
	api.nvim_buf_set_var(bufnr, 'title', {
		saved_body = title;
		body = title;
		dirty = false;
    extmark = title_mark;
	})

  -- write details in buffer
  write_details(bufnr, issue)

	-- write description
	local desc_mark = write_block(description, {bufnr=bufnr; mark=true; trailing_lines=3})
	api.nvim_buf_set_var(bufnr, 'description', {
		saved_body = description,
		body = description,
		dirty = false;
    extmark = desc_mark;
	})

  -- reactions
  if issue.reactions.total_count > 0 then
    local reactions_vt = {}
    for reaction, count in pairs(issue.reactions) do
      local emoji = require'octo.util'.reaction_map[reaction]
      if emoji and count > 0 then
        table.insert(reactions_vt, {'', 'OctoNvimBubble1'})
        table.insert(reactions_vt, {emoji, 'OctoNvimBubble2'})
        table.insert(reactions_vt, {'', 'OctoNvimBubble1'})
        table.insert(reactions_vt, {format(' %s ', count), 'Normal'})
      end
    end
	  api.nvim_buf_set_virtual_text(bufnr, OCTO_VT_NS, api.nvim_buf_line_count(bufnr) - 2, reactions_vt, {})
  end

	-- request issue comments
	api.nvim_buf_set_var(bufnr, 'comments', {})
  local comments_count = tonumber(issue['comments'])
  local comments_processed = 0
	if comments_count > 0 then
    gh.run({
      args = {'api', format('repos/%s/issues/%d/comments', repo, number)};
      cb = function(response)
        local resp = json.parse(response)
        for _, c in ipairs(resp) do
          write_comment(bufnr, c)
          comments_processed = comments_processed + 1
        end
      end
    })
	end

  local status = vim.wait(5000, function()
    return comments_processed == comments_count
  end, 200)

  -- show signs
  render_signcolumn(bufnr)

  -- drop undo history
  vim.fn['octo#clear_history']()

  -- reset modified option
  api.nvim_buf_set_option(bufnr, 'modified', false)

  vim.cmd [[ augroup octo_buffer_autocmds ]]
  vim.cmd [[ au! * <buffer> ]]
  vim.cmd [[ au TextChanged <buffer> lua require"octo".render_signcolumn() ]]
  vim.cmd [[ au TextChangedI <buffer> lua require"octo".render_signcolumn() ]]
  vim.cmd [[ augroup END ]]
end

local function get_url(url, params)
	url = url .. '?foo=bar'
	for k, v in pairs(params) do
		url = format('%s\\&%s=%s', url, k, v)
	end
	return url
end

local function get_repo_issues(repo, params)

	local query_params = {
		state = params.state or 'open';
		per_page = params.per_page or 50;
		filter = params.filter;
		labels = params.labels;
		since = params.since
	}

	local query = get_url(format('repos/%s/issues', repo), query_params)
  local body = gh.run({
    args = {'api', query};
    mode = 'sync';
  })

	local issues = json.parse(body)

  -- TODO: filter out pull_requests (NOT WORKING)
  vim.tbl_filter(function(e)
    return e.pull_request == nil
  end, issues)

	return issues
end

local function load_issue()
  local bufname = vim.fn.bufname()
  local repo, number = string.match(bufname, 'github://(.+)/(%d+)')
  if not repo or not number then
		api.nvim_err_writeln('Incorrect github url: '..bufname)
    return
  end

  gh.run({
    args = {'api', format('repos/%s/issues/%s', repo, number)};
    cb = function(output)
      create_issue_buffer(json.parse(output) , repo)
    end
  })
end

local function get_issue(repo, number)
  if not repo then repo = get_remote_name() end
  if not repo then print("Cant find repo name"); return end
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

	-- collect comment metadata
	update_issue_metadata(bufnr)

	-- title & description
	local title_metadata = api.nvim_buf_get_var(bufnr, 'title')
	local desc_metadata = api.nvim_buf_get_var(bufnr, 'description')
	if title_metadata.dirty or desc_metadata.dirty then

		-- trust but verify
		if string.find(title_metadata['body'], '\n') then
			api.nvim_err_writeln("Title can't contains new lines")
			return
		elseif title_metadata['body'] == '' then
			api.nvim_err_writeln("Title can't be blank")
			return
		end

    gh.run({
      args = {
        'api', '-X', 'PATCH',
        '-f', format('title=%s', title_metadata['body']),
        '-f', format('body=%s', desc_metadata['body']),
        format('repos/%s/issues/%s', repo, number)
      };
      cb = function(output)
        local resp = json.parse(output)

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
    })
	end

	-- comments
	local comments = api.nvim_buf_get_var(bufnr, 'comments')
	for _, metadata in ipairs(comments) do
		if is_blank(metadata['body']) then
			-- remove comment?
			local choice = vim.fn.confirm("Comment body can't be blank, remove comment?", "&Yes\n&No\n&Cancel", 2)
			if choice == 1 then
        gh.run({
          args = {
            'api', '-X', 'DELETE',
            format('repos/%s/issues/comments/%s', repo, metadata['id'])
          };
          cb = function(_)
            -- TODO: do not reload whole issue, but just remove comment
			      get_issue(repo, number)
          end
        })
			end
		elseif metadata['body'] ~= metadata['saved_body'] then
      gh.run({
        args = {
          'api', '-X', 'PATCH',
          '-f', format('body=%s', metadata['body']),
          format('repos/%s/issues/comments/%s', repo, metadata['id'])
        };
        cb = function(output)
          local resp = json.parse(output)
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
      })
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

  gh.run({
    args = {
      'api', '-X', 'POST',
      '-f', format('body=%s', NO_BODY_MSG),
      format('repos/%s/issues/%s/comments', repo, number)
    };
    cb = function(output)
      local resp = json.parse(output)
      if nil ~= resp['issue_url'] then
        -- TODO: do not reload issue, just add new comment at the bottom
        get_issue(repo, number)
      end
    end
  })
end

local function new_issue(repo)
  if not repo then repo = get_remote_name() end
  gh.run({
    args = {
      'api', '-X', 'POST',
      '-f', format('title=%s', 'title'),
      '-f', format('body=%s', NO_BODY_MSG),
      format('repos/%s/issues', repo)
    };
    cb = function(output)
      create_issue_buffer(json.parse(output), repo)
    end
  })
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

  gh.run({
    args = {
      'api', '-X', 'PATCH',
      '-f', format('state=%s', state),
      format('repos/%s/issues/%s', repo, number)
    };
    cb = function(output)
      local resp = json.parse(output)
      if state == resp['state'] then
        api.nvim_buf_set_var(bufnr, 'state', resp['state'])
        -- TODO: do not reload issue, just header
        get_issue(repo, resp['number'])
        print('Issue state changed to: '..resp['state'])
      end
    end
  })
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
		local issues = get_repo_issues(repo)
		local entries = {}
		for _,i in ipairs(issues) do
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
  if vim.bo.ft ~= 'octo_issue' then api.nvim_err_writeln('Not in octo buffer') return end

  local number_ok, number = pcall(api.nvim_buf_get_var, 0, 'number')
  if not number_ok then api.nvim_err_writeln('Missing octo metadata') return end
  local repo_ok, repo = pcall(api.nvim_buf_get_var, 0, 'repo')
  if not repo_ok then api.nvim_err_writeln('Missing octo metadata') return end

  vim.validate{
    action = {action,
      function(a)
        return vim.tbl_contains({'add', 'remove'}, a)
      end,
      'add or remove'
    },
    kind = {kind,
      function(a)
        return vim.tbl_contains({'assignees', 'labels', 'requested_reviewers'}, a)
      end,
      'assignees, labels or requested_reviewers'
    },
  }

  local endpoint
  if kind == 'requested_reviewers' then
    endpoint = 'pulls'
  else
    endpoint = 'issues'
  end

  local url = format('repos/%s/%s/%d/%s', repo, endpoint, number, kind)
  if kind == 'labels' and action == 'remove' then
    url = format('%s/%s', url, value)
  end

  local method
  if action == 'add' then
	  method = 'POST'
  elseif action == 'remove' then
	  method = 'DELETE'
  end

  -- gh does not allow array parameters at the moment
  -- workaround: https://github.com/cli/cli/issues/1484
  local cmd = format([[ jq -n '{"%s":["%s"]}' | gh api -X %s %s --input - ]], kind, value, method, url)
  local job = Job:new({
    command = "sh";
    args = {'-c', cmd};
    on_exit = vim.schedule_wrap(function(_, _, _)
      -- TODO: do not reload issue, just header
      get_issue(repo, number)
    end)
  })
  job:start()
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
  get_remote_name = get_remote_name;
}
