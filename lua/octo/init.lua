local gh = require('octo.gh')
local util = require('octo.util')
local signs = require('octo.signs')
local hl = require('octo.highlights')
local vim = vim
local api = vim.api
local max = math.max
local format = string.format
local json = {
	parse = vim.fn.json_decode;
	stringify = vim.fn.json_encode;
}

local M = {}

-- sign definitions
signs.setup()

-- constants
local OCTO_EM_NS = api.nvim_create_namespace('octo_marks')
local OCTO_VT_NS = api.nvim_create_namespace('octo_virtualtexts')
local OCTO_VT1_NS = api.nvim_create_namespace('octo_virtualtexts1')
local NO_BODY_MSG = 'No description provided.'

-- autocommands
vim.cmd [[ augroup octo_autocmds ]]
vim.cmd [[ autocmd!]]
vim.cmd [[ au BufReadCmd github://* lua require'octo.commands'.load_issue() ]]
vim.cmd [[ au BufWriteCmd github://* lua require'octo.commands'.save_issue() ]]
vim.cmd [[ augroup END ]]

function M.get_extmark_region(bufnr, mark)
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

function M.update_metadata(metadata, start_line, end_line, text)
	metadata['start_line'] = start_line
	metadata['end_line'] = end_line
	if vim.fn.trim(text) ~= vim.fn.trim(metadata['saved_body']) then
		metadata['dirty'] = true
	else
		metadata['dirty'] = false
	end
	metadata['body'] = text
end

function M.update_issue_metadata(bufnr)

	local mark, text, start_line, end_line, metadata

	-- title
	metadata = api.nvim_buf_get_var(bufnr, 'title')
	mark = api.nvim_buf_get_extmark_by_id(bufnr, OCTO_EM_NS, metadata.extmark, {details=true})
	start_line, end_line, text = M.get_extmark_region(bufnr, mark)
	M.update_metadata(metadata, start_line, end_line, text)
	api.nvim_buf_set_var(bufnr, 'title', metadata)

	-- description
	metadata = api.nvim_buf_get_var(bufnr, 'description')
	mark = api.nvim_buf_get_extmark_by_id(bufnr, OCTO_EM_NS, metadata.extmark, {details=true})
	start_line, end_line, text = M.get_extmark_region(bufnr, mark)
	if text == '' then
		-- description has been removed
		-- the space in ' ' is crucial to prevent this block of code from repeating on TextChanged(I)?
		api.nvim_buf_set_lines(bufnr, start_line, start_line+1, false, {' ',''})
		local winnr = api.nvim_get_current_win()
		api.nvim_win_set_cursor(winnr, {start_line+1, 0})
	end
	M.update_metadata(metadata, start_line, end_line, text)
	api.nvim_buf_set_var(bufnr, 'description', metadata)

	-- comments
	local comments = api.nvim_buf_get_var(bufnr, 'comments')
	for i, m in ipairs(comments) do
		metadata = m
		mark = api.nvim_buf_get_extmark_by_id(bufnr, OCTO_EM_NS, metadata.extmark, {details=true})
		start_line, end_line, text = M.get_extmark_region(bufnr, mark)

		if text == '' then
			-- comment has been removed
			-- the space in ' ' is crucial to prevent this block of code from repeating on TextChanged(I)?
			api.nvim_buf_set_lines(bufnr, start_line, start_line+1, false, {' ', ''})
			local winnr = api.nvim_get_current_win()
			api.nvim_win_set_cursor(winnr, {start_line+1, 0})

		end

		M.update_metadata(metadata, start_line, end_line, text)
		comments[i] = metadata
	end
	api.nvim_buf_set_var(bufnr, 'comments', comments)
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

function M.write_title(bufnr, issue)
  local title = issue['title']
	local title_mark = write_block(title, {bufnr=bufnr; mark=true; trailing_lines=1;})
	api.nvim_buf_set_var(bufnr, 'title', {
		saved_body = title;
		body = title;
		dirty = false;
    extmark = title_mark;
	})
end

function M.write_description(bufnr, issue)
	local description = string.gsub(issue['body'], '\r\n', '\n')
	local desc_mark = write_block(description, {bufnr=bufnr; mark=true; trailing_lines=3;})
	api.nvim_buf_set_var(bufnr, 'description', {
		saved_body = description,
		body = description,
		dirty = false;
    extmark = desc_mark;
	})
end

function M.write_reactions(bufnr, issue)
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
end

function M.write_details(bufnr, issue)

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
    table.insert(assignees_vt, {'No one assigned ', 'OctoNvimDetailsValue'})
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
      table.insert(requested_reviewers_vt, {'No requested reviewers', 'OctoNvimDetailsValue'})
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
      table.insert(reviewers_vt, {'No reviewers', 'OctoNvimDetailsValue'})
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
      table.insert(labels_vt, {'', hl.create_highlight(label.color, {mode='foreground'})})
      table.insert(labels_vt, {label.name, hl.create_highlight(label.color, {})})
      table.insert(labels_vt, {'', hl.create_highlight(label.color, {mode='foreground'})})
      table.insert(labels_vt, {' ', 'OctoNvimDetailsLabel'})
		end
	else
    table.insert(labels_vt, {'None yet', 'OctoNvimDetailsValue'})
	end
  api.nvim_buf_set_virtual_text(bufnr, OCTO_VT_NS, api.nvim_buf_line_count(bufnr) - 1, labels_vt, {})

  write_block({''}, {bufnr=bufnr; mark=false;})
end

function M.write_comment(bufnr, comment)

  -- heading
	write_block({'', ''}, {bufnr=bufnr; mark=false;})
	local header_vt = {
		{format('On %s ', comment.created_at), 'OctoNvimCommentHeading'},
		{comment.user.login, 'OctoNvimCommentUser'},
		{' commented', 'OctoNvimCommentHeading'}
	}
	api.nvim_buf_set_virtual_text(bufnr, OCTO_VT_NS, api.nvim_buf_line_count(bufnr) - 2, header_vt, {})

  -- body
  local comment_body = string.gsub(comment['body'], '\r\n', '\n')
  if vim.startswith(comment_body, NO_BODY_MSG) then comment_body = ' ' end
  local content = vim.split(comment_body, '\n', true)
  vim.list_extend(content, {'', '', ''})
	local comment_mark = write_block(content, {bufnr=bufnr; mark=true;})

  -- reactions
  M.write_reactions(bufnr, comment)

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

function M.create_issue_buffer(issue, repo)
	if not issue['id'] then
		api.nvim_err_writeln(format('Cannot find issue in %s', repo))
		return
	end

	local iid = issue['id']
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
  M.write_title(bufnr, issue)

  -- write details in buffer
  M.write_details(bufnr, issue)

	-- write description
  M.write_description(bufnr, issue)

  -- write reactions
  M.write_reactions(bufnr, issue)

	-- write issue comments
	api.nvim_buf_set_var(bufnr, 'comments', {})
  local comments_count = tonumber(issue['comments'])
  local comments_processed = 0
	if comments_count > 0 then
    gh.run({
      args = {'api', format('repos/%s/issues/%d/comments', repo, number)};
      cb = function(response)
        local resp = json.parse(response)
        for _, c in ipairs(resp) do
          M.write_comment(bufnr, c)
          comments_processed = comments_processed + 1
        end
      end
    })
	end

  local status = vim.wait(5000, function()
    return comments_processed == comments_count
  end, 200)

  -- show signs
  M.render_signcolumn(bufnr)

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

function M.render_signcolumn(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()
	local bufname = api.nvim_buf_get_name(bufnr)
  if not vim.startswith(bufname, 'github://') then return end

	local issue_dirty = false

	-- update comment metadata (lines, etc.)
	M.update_issue_metadata(bufnr)

	-- clear all signs
	signs.unplace(bufnr)

	-- clear virtual texts
	api.nvim_buf_clear_namespace(bufnr, OCTO_VT1_NS, 0, -1)

	-- title
	local title = api.nvim_buf_get_var(bufnr, 'title')
	if title['dirty'] then issue_dirty = true end
	local start_line = title['start_line']
	local end_line = title['end_line']
	signs.place_signs(bufnr, start_line, end_line, title['dirty'])

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
	signs.place_signs(bufnr, start_line, end_line, desc.dirty)

	-- description virtual text
	if util.is_blank(desc['body']) then
		local desc_vt = {{NO_BODY_MSG, 'OctoNvimEmpty'}}
		api.nvim_buf_set_virtual_text(bufnr, OCTO_VT1_NS, start_line, desc_vt, {})
	end

	-- comments
	local comments = api.nvim_buf_get_var(bufnr, 'comments')
	for _, c in ipairs(comments) do
		if c.dirty then issue_dirty = true end
		start_line = c['start_line']
		end_line = c['end_line']
		signs.place_signs(bufnr, start_line, end_line, c.dirty)

		-- comment virtual text
		if util.is_blank(c['body']) then
			local comment_vt = {{NO_BODY_MSG, 'OctoNvimEmpty'}}
			api.nvim_buf_set_virtual_text(bufnr, OCTO_VT1_NS, start_line, comment_vt, {})
		end
	end

	-- reset modified option
	if not issue_dirty then
		api.nvim_buf_set_option(bufnr, 'modified', false)
	end
end

return M
