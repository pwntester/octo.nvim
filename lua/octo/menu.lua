local actions = require('telescope.actions')
local finders = require('telescope.finders')
local pickers = require('telescope.pickers')
local utils = require('telescope.utils')
local previewers = require('telescope.previewers')
local conf = require('telescope.config').values
local make_entry = require('telescope.make_entry')
local Job = require('plenary.job')
local util = require('octo.util')

local format = string.format
local defaulter = utils.make_default_callable
local flatten = vim.tbl_flatten
local api = vim.api
local bat_options = {"bat" , "--style=plain" , "--color=always" , "--paging=always" , '--decorations=never','--pager=less'}

-- most of this code was taken from https://github.com/nvim-telescope/telescope-github.nvim/blob/master/lua/telescope/_extensions/ghcli.lua
-- thanks @windwp!

local function parse_opts(opts,target)
  local query = {}
  local tmp_table = {}
  if target == 'issue' then
    tmp_table = {'author' , 'assigner' , 'mention' , 'label' , 'milestone' , 'state' , 'limit' }
  elseif target == 'pr' then
    tmp_table = {'assigner' , 'label' , 'state' , 'base' , 'limit' }
  elseif target == 'gist' then
    tmp_table = {'public' , 'secret'}
    if opts.public then opts.public = ' ' end
    if opts.secret then opts.secret = ' ' end
  end

  for _, value in pairs(tmp_table) do
    if opts[value] then
      table.insert(query, format('--%s %s',value, opts[value]))
    end
  end
  return table.concat(query, ' ')
end

local function open_in_browser(type, repo)
  return function(prompt_bufnr)
    local selection = actions.get_selected_entry(prompt_bufnr)
    actions.close(prompt_bufnr)
    local tmp_table = vim.split(selection.value,"\t");
    if vim.tbl_isempty(tmp_table) then
      return
    end
    local cmd
    if not repo or repo == '' then
      cmd = format('gh %s view --web %s', type, tmp_table[1])
    else
      cmd = format('gh %s view --web %s -R %s', type, tmp_table[1], repo)
    end
    os.execute(cmd)
  end
end

--
-- ISSUES
--

local function open_issue(repo)
  return function(prompt_bufnr)
    local selection = actions.get_selected_entry(prompt_bufnr)
    actions.close(prompt_bufnr)
    local tmp_table = vim.split(selection.value,"\t");
    if vim.tbl_isempty(tmp_table) then
      return
    end
    vim.cmd(string.format([[ lua require'octo.commands'.get_issue('%s', '%s') ]], repo, tmp_table[1]))
  end
end

local function issues(repo, opts)
  opts = opts or {}
  opts.limit = opts.limit or 100
  local opts_query = parse_opts(opts , 'issue')
  if not repo or repo == vim.NIL then repo = util.get_remote_name() end
  if not repo then api.nvim_err_writeln('Cannot find repo'); return end
  local cmd = format('gh issue list %s -R %s', opts_query, repo)
  local results = vim.split(utils.get_os_command_output(cmd), '\n')

  if #results == 0 or #results == 1 and results[1] == '' then
    api.nvim_err_writeln(format("There are no matching issues in %s.", repo))
    return
  end

  pickers.new(opts, {
    prompt_title = 'Issues',
    finder = finders.new_table {
      results = results,
      entry_maker = make_entry.gen_from_string(opts),
    },
    sorter = conf.file_sorter(opts),
    previewer = previewers.new_termopen_previewer{
      get_command = function(entry)
        local tmp_table = vim.split(entry.value,"\t");
        if vim.tbl_isempty(tmp_table) then
          return {"echo", ""}
        end
        return { 'gh' ,'issue' , 'view', tmp_table[1], '-R', repo }

      end
    },
    attach_mappings = function(_, map)
      map('i', '<CR>', open_issue(repo))
      map('i', '<c-t>', open_in_browser('issue', repo))
      return true
    end
  }):find()
end

--
-- GISTS
--

local gist_previewer = defaulter(function(opts)
  return previewers.new_termopen_previewer {
    get_command = opts.get_command or function(entry)
      local tmp_table = vim.split(entry.value,"\t");
      if vim.tbl_isempty(tmp_table) then
        return {"echo", ""}
      end
      local result={ 'gh' ,'gist' ,'view',tmp_table[1] ,'|'}
      if vim.fn.executable("bat") then
        table.insert(result , bat_options)
      else
        table.insert(result , "less")
      end
      return flatten(result)
    end
  }
end, {})

local function open_gist(prompt_bufnr)
  local selection = actions.get_selected_entry(prompt_bufnr)
  actions.close(prompt_bufnr)
  local tmp_table = vim.split(selection.value,"\t");
  if vim.tbl_isempty(tmp_table) then
    return
  end
  local gist_id = tmp_table[1]
  local text = utils.get_os_command_output('gh gist view ' .. gist_id .. ' -r')
  if text and vim.api.nvim_buf_get_option(vim.api.nvim_get_current_buf(), "modifiable") then
    vim.api.nvim_put(vim.split(text,'\n'), 'b', true, true)
  end
end

local function gists(opts)
  opts = opts or {}
  opts.limit = opts.limit or 100
  local opts_query = parse_opts(opts , 'gist')
  local cmd = format('gh gist list %s', opts_query)
  local results = vim.split(utils.get_os_command_output(cmd), '\n')

  pickers.new(opts, {
    prompt_title = 'Gists' ,
    finder = finders.new_table {
      results = results,
      entry_maker = make_entry.gen_from_string(opts),
    },
    previewer = gist_previewer.new(opts),
    sorter = conf.file_sorter(opts),
    attach_mappings = function(_,map)
      map('i', '<CR>', open_gist)
      map('i', '<c-t>', open_in_browser('gist'))
      return true
    end
  }):find()
end

--
-- PULL REQUESTS
--

local function checkout_pr(repo)
  return function(prompt_bufnr)
    local selection = actions.get_selected_entry(prompt_bufnr)
    actions.close(prompt_bufnr)
    local tmp_table = vim.split(selection.value,"\t");
    if vim.tbl_isempty(tmp_table) then
      return
    end
    local args = {"pr", "checkout" ,tmp_table[1], '-R', repo}
    if repo == '' then
      args = {"pr", "checkout" ,tmp_table[1]}
    end
    local job = Job:new({
        enable_recording = true ,
        command = "gh",
        args = args,
        on_stderr = function(_, data)
          print(data)
        end
      })
    -- need to display result in quickfix
    job:sync()
  end
end

local function pull_requests(repo, opts)
  opts = opts or {}
  opts.limit = opts.limit or 100
  local opts_query = parse_opts(opts , 'pr')
  if not repo or repo == vim.NIL then repo = util.get_remote_name() end
  if not repo then print('Cannot find repo'); return end
  local cmd = format('gh pr list %s -R %s', opts_query, repo)
  local results = vim.split(utils.get_os_command_output(cmd) , '\n')

  if #results == 0 or #results == 1 and results[1] == '' then
    api.nvim_err_writeln(format("There are no matching pull requests in %s.", repo))
    return
  end

  pickers.new(opts, {
    prompt_title = 'Pull Requests' ,
    finder = finders.new_table {
      results = results,
      entry_maker = make_entry.gen_from_string(opts),
    },
    previewer = previewers.new_termopen_previewer{
      get_command = function(entry)
        local tmp_table = vim.split(entry.value,"\t");
        if vim.tbl_isempty(tmp_table) then
          return {"echo", ""}
        end
        return { 'gh' ,'pr' , 'view', tmp_table[1], '-R', repo }
      end
    },
    sorter = conf.file_sorter(opts),
    attach_mappings = function(_,map)
      map('i', '<CR>', open_issue(repo))
      map('i', '<c-o>', checkout_pr(repo))
      map('i', '<c-t>', open_in_browser('pr'))
      return true
    end
  }):find()
end

return {
  issues = issues;
  pull_requests = pull_requests;
  gists = gists;
}
