local gh = require'octo.gh'
local util = require'octo.util'
local menu = require'octo.menu'
local octo = require'octo'
local constants = require('octo.constants')
local api = vim.api
local format = string.format
local json = {
	parse = vim.fn.json_decode;
	stringify = vim.fn.json_encode;
}
local Job = require('plenary.job')

local M = {}

function table.pack(...)
  return { n = select("#", ...), ... }
end

local commands = {
  issue = {
    create = function(repo)
      M.create_issue(repo)
    end;
    edit = function(...)
      M.get_issue(...)
    end;
    close = function()
      M.change_issue_state('closed')
    end;
    open = function()
      M.change_issue_state('open')
    end;
    list = function(repo, ...)
      local args = table.pack(...)
      local opts = {}
      for i=1,args.n do
        local kv = vim.split(args[i], '=')
        opts[kv[1]] = kv[2]
      end
      menu.issues(repo, opts);
    end;
  };
  pr = {
    list = function(repo, ...)
      local args = table.pack(...)
      local opts = {}
      for i=1,args.n do
        local kv = vim.split(args[i], '=')
        opts[kv[1]] = kv[2]
      end
      menu.pull_requests(repo, opts)
    end;
  };
  gist = {
    list = function(repo, ...)
      local args = table.pack(...)
      local opts = {}
      for i=1,args.n do
        local kv = vim.split(args[i], '=')
        opts[kv[1]] = kv[2]
      end
      menu.gists(repo, opts)
    end;
  };
  comment = {
    add = function()
      M.add_comment()
    end;
    delete = function()
      M.delete_comment()
    end;
  };
  label = {
    add = function(value)
      M.issue_action('add', 'labels', value)
    end;
    delete = function(value)
      M.issue_action('delete', 'labels', value)
    end;
  };
  assignee = {
    add = function(value)
      M.issue_action('add', 'assignees', value)
    end;
    delete = function(value)
      M.issue_action('delete', 'assignees', value)
    end;
  };
  reviewer = {
    add = function(value)
      M.issue_action('add', 'requested_reviewers', value)
    end;
    delete = function(value)
      M.issue_action('delete', 'requested_reviewers', value)
    end;
  };
  reaction = {
    add = function(reaction)
      M.reaction_action('add',  reaction)
    end;
    delete = function(reaction)
      M.reaction_action('delete', reaction)
    end;
  };
}

function M.octo(object, action, ...)
  local o = commands[object]
  if not o then
    print('Incorrect argument, valid objects are:'.. vim.inspect(vim.tbl_keys(commands)))
    return
  else
    local a = o[action]
    if not a then
      print('Incorrect action, valid actions are:'.. vim.inspect(vim.tbl_keys(o)))
      return
    else
      a(...)
    end
  end
end

function M.add_comment()
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
      '-f', format('body=%s', constants.NO_BODY_MSG),
      format('repos/%s/issues/%s/comments', repo, number)
    };
    cb = function(output)
      local comment = json.parse(output)
      if nil ~= comment['issue_url'] then
        octo.write_comment(bufnr, comment)
        vim.fn.execute('normal! Gkkk')
        vim.fn.execute('startinsert')
      end
    end
  })
end

function M.delete_comment()
  local bufnr = api.nvim_get_current_buf()
	local repo = api.nvim_buf_get_var(bufnr, 'repo')
  local comment, start_line, end_line = unpack(util.get_comment_at_cursor(bufnr))
  if not comment then
    print('The cursor does not seem to be located at any comment')
    return
  end
  local choice = vim.fn.confirm("Delete comment?", "&Yes\n&No\n&Cancel", 2)
  if choice == 1 then
    gh.run({
      args = {
        'api', '-X', 'DELETE',
        format('repos/%s/issues/comments/%s', repo, comment.id)
      };
      cb = function(_)
        api.nvim_buf_set_lines(bufnr, start_line-2, end_line+1, false, {})
	      api.nvim_buf_clear_namespace(bufnr, comment.namespace, 0, -1)
	      api.nvim_buf_clear_namespace(bufnr, constants.OCTO_REACTIONS_VT_NS, start_line-2, end_line+1)
        api.nvim_buf_del_extmark(bufnr, constants.OCTO_EM_NS, comment.extmark)
	      local comments = api.nvim_buf_get_var(bufnr, 'comments')
        local updated = {}
        for _, c in ipairs(comments) do
          if c.id ~= comment.id then table.insert(updated, c) end
        end
	      api.nvim_buf_set_var(bufnr, 'comments', updated)
      end
    })
  end
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
        octo.write_state(bufnr)
        octo.write_details(bufnr, resp, 3)
        print('Issue state changed to: '..resp['state'])
      end
    end
  })
end

function M.create_issue(repo)
  if not repo then repo = util.get_remote_name() end
  gh.run({
    args = {
      'api', '-X', 'POST',
      '-f', format('title=%s', 'title'),
      '-f', format('body=%s', constants.NO_BODY_MSG),
      format('repos/%s/issues', repo)
    };
    cb = function(output)
      octo.create_issue_buffer(json.parse(output), repo)
    end
  })
end

function M.get_issue(...)
  local repo, number
  local args = table.pack(...)
  if args.n == 0 then
    print('Missing arguments')
    return
  elseif args.n == 1 then
    repo = util.get_remote_name()
    number = tonumber(args[1])
  elseif args.n == 2 then
    repo = args[1]
    number = tonumber(args[2])
  else
    print('Unexpected arguments')
    return
  end
  if not repo then print("Cant find repo name"); return end
  if not number then print('Missing issue number'); return end
  vim.cmd(format('edit octo://%s/%s', repo, number))
end

function M.issue_action(action, kind, value)
  local bufnr = api.nvim_get_current_buf()
  if vim.bo.ft ~= 'octo_issue' then api.nvim_err_writeln('Not in octo buffer') return end

  local number_ok, number = pcall(api.nvim_buf_get_var, 0, 'number')
  if not number_ok then api.nvim_err_writeln('Missing octo metadata') return end
  local repo_ok, repo = pcall(api.nvim_buf_get_var, 0, 'repo')
  if not repo_ok then api.nvim_err_writeln('Missing octo metadata') return end

  vim.validate{
    action = {action,
      function(a)
        return vim.tbl_contains({'add', 'delete'}, a)
      end,
      'add or delete'
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
  if kind == 'labels' and action == 'delete' then
    url = format('%s/%s', url, value)
  end

  local method
  if action == 'add' then
	  method = 'POST'
  elseif action == 'delete' then
	  method = 'DELETE'
  end

  -- gh does not allow array parameters at the moment
  -- workaround: https://github.com/cli/cli/issues/1484
  local cmd = format([[ jq -n '{"%s":["%s"]}' | gh api -X %s %s --input - ]], kind, value, method, url)
  local job = Job:new({
    command = "sh";
    args = {'-c', cmd};
    on_exit = vim.schedule_wrap(function(_, _, _)
      gh.run({
        args = {'api', format('repos/%s/issues/%s', repo, number)};
        cb = function(output)
          octo.write_details(bufnr, json.parse(output), 3)
        end
      })
    end)
  })
  job:start()
end

function M.reaction_action(action, reaction)
  local bufnr = api.nvim_get_current_buf()

  local number_ok, number = pcall(api.nvim_buf_get_var, bufnr, 'number')
  if not number_ok then api.nvim_err_writeln('Missing octo metadata') return end
  local repo_ok, repo = pcall(api.nvim_buf_get_var, bufnr, 'repo')
  if not repo_ok then api.nvim_err_writeln('Missing octo metadata') return end

  local url, method, line, cb_url
  local comment = util.get_comment_at_cursor(bufnr)

  if comment then
    comment = comment[1]
    cb_url = format('repos/%s/issues/comments/%d', repo, comment.id)
    line = comment.reaction_line
    if action == 'add' then
      method = 'POST'
      url = format('repos/%s/issues/comments/%d/reactions', repo, comment.id)
    else
      -- TODO: we need reaction id
      -- get list of reactions for issue and filter by user login and reaction
      print('Not implemeted')
      method = 'DELETE'
      local reaction_id = 0
      url = format('repos/%s/issues/comments/%s/reactions/%d', repo, comment.id, reaction_id)
      return
    end
  else
    cb_url = format('repos/%s/issues/%d', repo, number)
    line = api.nvim_buf_get_var(bufnr, 'reaction_line')
    if action == 'add' then
      method = 'POST'
      url = format('repos/%s/issues/%d/reactions', repo, number)
    else
      -- TODO: we need reaction id
      -- get list of reactions for issue and filter by user login and reaction
      print('Not implemeted')
      method = 'DELETE'
      local reaction_id = 0
      url = format('repos/%s/issues/%d/reactions/%d', repo, number, reaction_id)
      return
    end
  end

  gh.run({
    args = {
      'api', '-X', method,
      '-f', format('content=%s', reaction),
      url
    },
    cb = function(_)
      gh.run({
        args = {
          'api',
          cb_url
        };
        cb = function(output)
          print('FOO', line)
          octo.write_reactions(bufnr, json.parse(output), line)
        end
      })
    end
  })
end

return M
