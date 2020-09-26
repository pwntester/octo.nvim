local curl = require('curl')
local vim = vim
local api = vim.api
local max = math.max
local format = string.format
local json = {
    parse = vim.fn.json_decode;
    stringify = vim.fn.json_encode;
}
local NO_BODY_MSG = 'No description provided.'
local HIGHLIGHT_NAME_PREFIX = "octo"
local HIGHLIGHT_CACHE = {}
local HIGHLIGHT_MODE_NAMES = {
	background = "mb";
	foreground = "mf";
}

local function is_blank(s)
	return not(s ~= nil and s:match("%S") ~= nil)
end

local function check_error(status, resp)
	if status ~= 200 then
		if resp.message then
			api.nvim_err_writeln('Error: '..resp.message)
		end
		return true
	else
		return false
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
	local dirty_mod = 'clean'
	if is_dirty then dirty_mod = 'dirty' end
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
			api.nvim_command(format('highlight %s guifg=#%s', highlight_name, rgb_hex))
		else
			local r, g, b = rgb_hex:sub(1,2), rgb_hex:sub(3,4), rgb_hex:sub(5,6)
			r, g, b = tonumber(r,16), tonumber(g,16), tonumber(b,16)
			local fg_color
			if color_is_bright(r,g,b) then
				fg_color = "000000"
			else
				fg_color = "ffffff"
			end
			api.nvim_command(format('highlight %s guifg=#%s guibg=#%s', highlight_name, fg_color, rgb_hex))
		end
		HIGHLIGHT_CACHE[cache_key] = highlight_name
	end
	return highlight_name
end

local function details_win(current_bufnr)

    local labels = api.nvim_buf_get_var(current_bufnr, 'labels')
	local assignees = api.nvim_buf_get_var(current_bufnr, 'assignees')
    local milestone = api.nvim_buf_get_var(current_bufnr, 'milestone')

    local lines = {''}
	local hls = {}
	local line
	local longest_line = 10

	table.insert(lines, ' Labels:')
	if labels and #labels > 0 then
		for _, label in ipairs(labels) do
			line = format('  - ◖%s◗', label.name)
			local highlight_name = create_highlight(label.color, {})
			table.insert(lines, line)
			table.insert(hls, {
				['name'] = highlight_name;
				['line'] = #lines-1;
				['start'] = 4;
				['end'] = #line;
			})
			longest_line = max(longest_line, #line)
		end
	else
		line = '   None yet'
		table.insert(lines, line)
		longest_line = max(longest_line, #line)
	end
	table.insert(lines, '')

	table.insert(lines, ' Assignees:')
	if assignees and #assignees > 0 then
		for _, as in ipairs(assignees) do
			line = format('  - %s', as.login)
			table.insert(lines, line)
			longest_line = max(longest_line, #line)
		end
	else
		line = '   No one assigned '
		table.insert(lines, line)
		longest_line = max(longest_line, #line)
	end
	table.insert(lines, '')

	table.insert(lines, ' Milestone:')
	if milestone then
		line = format('  - %s (%s)', milestone.title, milestone.state)
		table.insert(lines, line)
		longest_line = max(longest_line, #line)
	else
		line = '   No milestone'
		table.insert(lines, line)
		longest_line = max(longest_line, #line)
	end
	table.insert(lines, '')

    local bufnr = api.nvim_create_buf(false, true)
    api.nvim_buf_set_lines(bufnr, 0, -1, true, lines)
	highlight(bufnr, hls)

    local current_win = api.nvim_get_current_win()
    local win_width = vim.fn.winwidth(current_win)
	local vertical_padding = 1
    local horizontal_padding = 1
    local popup_width = longest_line + 1
    local popup_height = #lines

    local opts = {
		relative = 'win';
		win = current_win;
		width = popup_width;
		height = popup_height;
		style = 'minimal';
		focusable = false;
        row = vertical_padding;
		col = win_width - horizontal_padding - popup_width;
	}

    local winnr = api.nvim_open_win(bufnr, false, opts)
	api.nvim_win_set_option(winnr, "winhighlight", "NormalFloat:NormalNC,EndOfBuffer:NormalNC")

	vim.cmd(format("autocmd BufLeave <buffer=%d> lua pcall(vim.api.nvim_win_close,%d,1);pcall(vim.cmd,'%dbw!')", current_bufnr, winnr, bufnr))

    return bufnr, winnr
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
    if text ~= metadata['saved_body'] then
        metadata['dirty'] = true
    else
        metadata['dirty'] = false
    end
    metadata['body'] = text
end


local function get_repo_name()
	local cmd = "git config --get remote.origin.url | sed -r 's/.*(\\@|\\/\\/)(.*)(\\:|\\/)([^:\\/]*)\\/([^\\/\\.]*)\\.git/\\4\\/\\5/'"
	return vim.fn.system(cmd):gsub('\n', '')
end

local function get_gh_token()
    return vim.fn.getenv('GITHUB_PAT')
end

local opts = {
    headers = {
        Accept = 'application/vnd.github.v3+json',
        ["Content-Type"] = 'application/json'
    }
}

-- get credentials from env var
opts['credentials'] = get_gh_token()

-- definitions
octo_em_ns = api.nvim_create_namespace('octo_marks')
octo_hl_ns = api.nvim_create_namespace('octo_highlights')
octo_vt_ns = api.nvim_create_namespace('octo_virtualtexts')

api.nvim_command('sign define clean_block_start text=┌')
api.nvim_command('sign define clean_block_end text=└')
api.nvim_command('sign define dirty_block_start text=┌ texthl=OctoNvimDirty')
api.nvim_command('sign define dirty_block_end text=└ texthl=OctoNvimDirty')
api.nvim_command('sign define dirty_block_middle text=│ texthl=OctoNvimDirty')
api.nvim_command('sign define clean_block_middle text=│')
api.nvim_command('sign define clean_line text=[')
api.nvim_command('sign define dirty_line text=[ texthl=OctoNvimDirty')

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
    if nil == bufnr or bufnr == 0 then
        bufnr = api.nvim_get_current_buf()
    end

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
    if desc['dirty'] then issue_dirty = true end
    start_line = desc['start_line']
    end_line = desc['end_line']
	place_signs(bufnr, start_line, end_line, desc['dirty'])

	-- description virtual text
	if is_blank(desc['body']) then
		local desc_vt = {{NO_BODY_MSG, 'OctoNvimEmpty'}}
		api.nvim_buf_set_virtual_text(bufnr, octo_vt_ns, start_line, desc_vt, {})
	end

    -- comments
    local comments = api.nvim_buf_get_var(bufnr, 'comments')
    for _, c in ipairs(comments) do
		if c['dirty'] then issue_dirty = true end
        start_line = c['start_line']
        end_line = c['end_line']
		place_signs(bufnr, start_line, end_line, c['dirty'])

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

	-- create buffer
	api.nvim_command(format('e octo://%s/%s', repo, number))
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

        -- autocommands
		vim.cmd(format('augroup octocmds_%s', bufnr))
		vim.cmd [[autocmd!]]
        vim.cmd(format('autocmd TextChanged  <buffer=%d> lua require("octo").render_signcolumn(%d)',bufnr,bufnr))
        vim.cmd(format('autocmd TextChangedI <buffer=%d> lua require("octo").render_signcolumn(%d)',bufnr,bufnr))
        vim.cmd(format('autocmd BufWriteCmd <buffer=%d> lua require("octo").save_issue(%d)',bufnr,bufnr))
        vim.cmd(format('autocmd BufEnter,BufNew <buffer=%d> lua require("octo").details_win(%d)',bufnr,bufnr))
		vim.cmd [[augroup END]]

        -- reset modified option
        api.nvim_buf_set_option(bufnr, 'modified', false)

		-- show details window
		details_win(bufnr)

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

            --vim.list_extend(content, {'', heading, '⠀⠀⠀'}) -- U+2800
            vim.list_extend(content, {heading, ''})

            -- body
            local cbody = string.gsub(c['body'], '\r\n', '\n')
			if cbody == NO_BODY_MSG then cbody = '' end
            write(cbody)
            --vim.list_extend(content, {'⠀⠀⠀', ''}) -- U+2800
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
    api.nvim_buf_set_option(bufnr, 'bufhidden', 'hide')
    api.nvim_buf_set_option(bufnr, 'swapfile', false)
    --api.nvim_command('execute "setlocal colorcolumn=" . join(range(81,335), ",")')

    local winnr = api.nvim_get_current_win()
    api.nvim_win_set_option(winnr, 'cursorline', false)
    api.nvim_win_set_option(winnr, 'number', false)

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
    --vim.list_extend(content, {'⠀⠀⠀'}) -- U+2800
    vim.list_extend(content, {'', ''})
    local title_metadata = {
        saved_body = title;
        body = title;
        dirty = false
    }
    api.nvim_buf_set_var(bufnr, 'title', title_metadata)

    -- write description
    write(body)
    --vim.list_extend(content, {'⠀⠀⠀',''}) -- U+2800
    vim.list_extend(content, {'','',''})
    local desc_metadata = {
        saved_body = body,
        body = body,
        dirty = false
    }
    api.nvim_buf_set_var(bufnr, 'description', desc_metadata)

    -- request issue comments
    api.nvim_buf_set_var(bufnr, 'comments', {})
    if tonumber(issue['comments']) > 0 then
        curl.request(comments_url, opts, write_comments)
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

local function list_issues(repo)

    if nil == repo or repo == '' then
		repo = get_repo_name()
    end

    local function choose_issue(response, status, headers)
        local issues = json.parse(response)
		if check_error(status, issues) then return end

        local count, total = process_link_header(headers)
        if count == nil and total == nil then
            count = #issues
            total = #issues
        end

        local source = {}
        for _,i in ipairs(issues) do
            table.insert(source, {
                id = i['id'];
                issue = i;
                number = i['number'];
                display = string.format('#%d - %s', i['number'], i['title']);
            })
        end
        local winnr = api.nvim_get_current_win()
        require'octo.ui'.floating_fuzzy_menu{
            inputs = source;
            prompt_position = 'top';
            leave_empty_space = true;
			height = 30;
            prompt = 'Search:';
            virtual_text = format('%d out of %d', count, total);
            callback = function(e, _, _)
                api.nvim_set_current_win(winnr)
                local bufnr = create_issue_buffer(e.issue, repo)
                api.nvim_win_set_buf(winnr, bufnr)
            end
        }

    end

    local issues_url = format('https://api.github.com/repos/%s/issues?state=open\\&per_page=50', repo)
    curl.request(issues_url, opts, choose_issue)
end

local function get_issue(number, repo)

    if nil == repo or repo == '' then
		repo = get_repo_name()
    end

	if not number then
        api.nvim_err_writeln('Missing argument: issue number')
		return
	elseif not repo then
        api.nvim_err_writeln('Missing argument: issue repo')
		return
	end

    local url = format('https://api.github.com/repos/%s/issues/%s', repo, number)

    local function load_issue(response, status)
        local resp = json.parse(response)
		if check_error(status, resp) then return end
        create_issue_buffer(resp, repo)
    end
    local url_opts = vim.deepcopy(opts)
    curl.request(url, url_opts, load_issue)
end

local function save_issue(bufnr)

	-- repo
    local repo = api.nvim_buf_get_var(bufnr, 'repo')

	if not repo then
        api.nvim_err_writeln('Buffer is not linked to a GitHub issue')
		return
	end

    -- collect comment metadata
    update_issue_metadata(bufnr)

    -- title
    local title_metadata = api.nvim_buf_get_var(bufnr, 'title')
    if title_metadata['dirty'] then
		if string.find(title_metadata['body'], '\n') then
			api.nvim_err_writeln("Title can't contains new lines")
			return
		elseif title_metadata['body'] == '' then
			api.nvim_err_writeln("Title can't be blank")
			return
		else
			local number = api.nvim_buf_get_var(bufnr, 'number')
			local update_url = format('https://api.github.com/repos/%s/issues/%s', repo, number)
			local function update_title(response, status)
				local resp = json.parse(response)
				if check_error(status, resp) then return end
				if title_metadata['body'] == resp['title'] then
					title_metadata['saved_body'] = resp['title']
					title_metadata['dirty'] = false
					api.nvim_buf_set_var(bufnr, 'title', title_metadata)
					render_signcolumn(bufnr)
					print('Saved!')
				end
			end
			local update_opts = vim.deepcopy(opts)
			update_opts['body'] = json.stringify({
				title = title_metadata['body']
			})
			update_opts['method'] = 'PATCH'
			curl.request(update_url, update_opts, update_title)
		end
    end

    -- description
    local desc_metadata = api.nvim_buf_get_var(bufnr, 'description')
    if desc_metadata['dirty'] then
		local number = api.nvim_buf_get_var(bufnr, 'number')
		local update_url = format('https://api.github.com/repos/%s/issues/%s', repo, number)
		local function update_desc(response, status)
			local resp = json.parse(response)
			if check_error(status, resp) then return end
			if desc_metadata['body'] == resp['body'] then
				desc_metadata['saved_body'] = resp['body']
				desc_metadata['dirty'] = false
				api.nvim_buf_set_var(bufnr, 'description', desc_metadata)
				render_signcolumn(bufnr)
				print('Saved!')
			end
		end
		local update_opts = vim.deepcopy(opts)
		update_opts['body'] = json.stringify({
			body = desc_metadata['body']
		})
		update_opts['method'] = 'PATCH'
		curl.request(update_url, update_opts, update_desc)
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
					get_issue(api.nvim_buf_get_var(bufnr, 'number'), repo)
				end
				local remove_opts = vim.deepcopy(opts)
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
            local update_opts = vim.deepcopy(opts)
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
            get_issue(number, repo)
        end
    end

    local url_opts = vim.deepcopy(opts)
    url_opts['body'] = json.stringify({
        body = NO_BODY_MSG
    })
    url_opts['method'] = 'POST'
    curl.request(url, url_opts, new_comment_cb)
end

local function new_issue(repo)

    if nil == repo or repo == '' then
		repo = get_repo_name()
    end

    local url = format('https://api.github.com/repos/%s/issues', repo)

    local function new_issue_cb(response, status)
        local resp = json.parse(response)
		if check_error(status, resp) then return end
        create_issue_buffer(resp, repo)
    end
    local url_opts = vim.deepcopy(opts)
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
            get_issue(resp['number'], repo)
        end
    end
    local update_opts = vim.deepcopy(opts)
    update_opts['body'] = json.stringify({
        state = state;
    })
    update_opts['method'] = 'PATCH'
    curl.request(update_url, update_opts, update_state)
end

return {
    change_issue_state = change_issue_state;
    get_issue = get_issue;
    new_issue = new_issue;
    list_issues = list_issues;
    save_issue = save_issue;
    render_signcolumn = render_signcolumn;
    new_comment = new_comment;
	details_win = details_win;
}
