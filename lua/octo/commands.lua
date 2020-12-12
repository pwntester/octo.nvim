local gh = require'octo.gh'
local util = require'octo.util'
local octo = require'octo'
local api = vim.api
local format = string.format
local json = {
	parse = vim.fn.json_decode;
	stringify = vim.fn.json_encode;
}
local Job = require('plenary.job')

local NO_BODY_MSG = 'No description provided.'
local M = {}

function M.load_issue()
  local bufname = vim.fn.bufname()
  local repo, number = string.match(bufname, 'github://(.+)/(%d+)')
  if not repo or not number then
		api.nvim_err_writeln('Incorrect github url: '..bufname)
    return
  end

  gh.run({
    args = {'api', format('repos/%s/issues/%s', repo, number)};
    cb = function(output)
      octo.create_issue_buffer(json.parse(output) , repo)
    end
  })
end

function M.get_issue(repo, number)
  if not repo then repo = util.get_remote_name() end
  if not repo then print("Cant find repo name"); return end
  vim.cmd(format('edit github://%s/%s', repo, number))
end

function M.save_issue(bufnr)
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
	octo.update_issue_metadata(bufnr)

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

        octo.render_signcolumn(bufnr)
        print('Saved!')
      end
    })
	end

	-- comments
	local comments = api.nvim_buf_get_var(bufnr, 'comments')
	for _, metadata in ipairs(comments) do
		if util.is_blank(metadata['body']) then
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
			      M.get_issue(repo, number)
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
            octo.render_signcolumn(bufnr)
            print('Saved!')
          end
        end
      })
		end
	end

	-- reset modified option
	api.nvim_buf_set_option(bufnr, 'modified', false)
end


function M.new_comment()
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
      local comment = json.parse(output)
      if nil ~= comment['issue_url'] then
        octo.write_comment(bufnr, comment)
        vim.fn.execute('normal! Gkkk')
      end
    end
  })
end

function M.new_issue(repo)
  if not repo then repo = util.get_remote_name() end
  gh.run({
    args = {
      'api', '-X', 'POST',
      '-f', format('title=%s', 'title'),
      '-f', format('body=%s', NO_BODY_MSG),
      format('repos/%s/issues', repo)
    };
    cb = function(output)
      octo.create_issue_buffer(json.parse(output), repo)
    end
  })
end

function M.change_issue_state(state)
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
        M.get_issue(repo, resp['number'])
        print('Issue state changed to: '..resp['state'])
      end
    end
  })
end

function M.issue_action(action, kind, value)
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
      M.get_issue(repo, number)
    end)
  })
  job:start()
end

return M
