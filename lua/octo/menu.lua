local actions = require('telescope.actions')
local finders = require('telescope.finders')
local pickers = require('telescope.pickers')
local sorters = require('telescope.sorters')

local opts = require('telescope.themes').get_dropdown({
  results_height = 25;
  results_width = 0.8;
  winblend = 20;
  borderchars = {
    prompt = {'▀', '▐', '▄', '▌', '▛', '▜', '▟', '▙' };
    results = {' ', '▐', '▄', '▌', '▌', '▐', '▟', '▙' };
    preview = {'▀', '▐', '▄', '▌', '▛', '▜', '▟', '▙' };
  }
})

local function encodeChar(chr)
	return string.format("%%%X",string.byte(chr))
end

local function encodeString(str)
	local output, _ = string.gsub(str,"[^%w]",encodeChar)
	return output
end

local function issues(repo, ...)
  if not repo then
    vim.api.nvim_err_writeln('Please specify a repo to get the issues from')
    return
  end

  local params = {}
  local args = { n = select("#", ...), ... }
  if #args > 0 then
    if #args % 2 ~= 0 then
      vim.api.nvim_err_writeln('Incorrect number of parameters, should be <repo> (<key> <value>)*')
    end
    for i=1,#args,1 do
      local key = vim.split(args[i], ':')[1]
      local value = vim.split(args[i], ":")[2]
      params[key] = encodeString(value)
    end
  end

  -- TODO: use params as part of the cache key

  if not vim.g.octo_last_results then vim.g.octo_last_results = {} end
  if not vim.g.octo_last_updatetime then vim.g.octo_last_updatetime = {} end

  local cache_timeout = 300 -- 5 min cache
  local current_time = os.time()
  local next_check
  if vim.g.octo_last_updatetime[repo] ~= nil then
    next_check = tonumber(vim.g.octo_last_updatetime[repo]) + cache_timeout
  else
    next_check = 0 -- now
  end

  local results = {}
  if current_time > next_check then
    local resp = require'octo'.get_repo_issues(repo, params)
    for _,i in ipairs(resp.issues) do
      table.insert(results, {
        number = i.number;
        title = i.title;
      })
    end
    local last_results = vim.api.nvim_get_var('octo_last_results')
    last_results[repo] = results
    vim.api.nvim_set_var('octo_last_results', last_results)

    local last_updatetime = vim.api.nvim_get_var('octo_last_updatetime')
    last_updatetime[repo] = current_time
    vim.api.nvim_set_var('octo_last_updatetime', last_updatetime)
  else
    results = vim.g.octo_last_results[repo]
  end

  local make_issue_entry = function(result)
    return {
      valid = true;
      value = tostring(result.number);
      ordinal = tostring(result.number);
      display = string.format('#%d - %s', result.number, result.title);
    }
  end

  local custom_mappings = function(prompt_bufnr, map)
    local run_command = function()
      local selection = actions.get_selected_entry(prompt_bufnr)
      actions.close(prompt_bufnr)
      local cmd = string.format([[ lua require'octo'.get_issue('%s', '%s') ]], selection.value, repo)
      vim.cmd [[stopinsert]]
      vim.cmd(cmd)
    end

    map('i', '<CR>', run_command)
    map('n', '<CR>', run_command)

    return true
  end

  pickers.new(opts, {
    prompt = '';
    finder = finders.new_table({
      results = results;
      entry_maker = make_issue_entry;
    });
    sorter = sorters.get_generic_fuzzy_sorter();
    attach_mappings = custom_mappings;
  }):find()
end


return {
  issues = issues;
}
