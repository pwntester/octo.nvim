local actions = require "telescope.actions"
local finders = require "telescope.finders"
local pickers = require "telescope.pickers"
local utils = require "telescope.utils"
local putils = require "telescope.previewers.utils"
local previewers = require "telescope.previewers"
local conf = require "telescope.config".values
local sorters = require "telescope.sorters"
local make_entry = require "telescope.make_entry"
local entry_display = require "telescope.pickers.entry_display"

local writers = require "octo.writers"
local reviews = require "octo.reviews"
local gh = require "octo.gh"
local util = require "octo.util"
local graphql = require "octo.graphql"
local hl = require "octo.highlights"

local format = string.format
local defaulter = utils.make_default_callable
local vim = vim
local flatten = vim.tbl_flatten
local api = vim.api
local json = {
  parse = vim.fn.json_decode,
  stringify = vim.fn.json_encode
}

local M = {}

local dropdown_opts = require('telescope.themes').get_dropdown({
  results_height = 15;
  width = 0.4;
  prompt_title = '';
  previewer = false;
  borderchars = {
    prompt = {'▀', '▐', '▄', '▌', '▛', '▜', '▟', '▙' };
    results = {' ', '▐', '▄', '▌', '▌', '▐', '▟', '▙' };
    preview = {'▀', '▐', '▄', '▌', '▛', '▜', '▟', '▙' };
  };
})

local function get_filter(opts, kind)
  local filter = ""
  local allowed_values = {}
  if kind == "issue" then
    allowed_values = {"since", "createdBy", "assignee", "mentioned", "labels", "milestone", "states"}
  elseif kind == "pull_request" then
    allowed_values = {"baseRefName", "headRefName", "labels", "states"}
  end

  for _, value in pairs(allowed_values) do
    if opts[value] then
      local val
      if #vim.split(opts[value], ",") > 1 then
        -- list
        val = vim.split(opts[value], ",")
      else
        -- string
        val = opts[value]
      end
      val = json.stringify(val)
      val = string.gsub(val, '"OPEN"', "OPEN")
      val = string.gsub(val, '"CLOSED"', "CLOSED")
      filter = filter .. value .. ":" .. val .. ","
    end
  end

  return filter
end

local function open(repo, what, command)
  return function(prompt_bufnr)
    local selection = actions.get_selected_entry(prompt_bufnr)
    actions.close(prompt_bufnr)
    if command == 'split' then
      vim.cmd [[:sbuffer %]]
    elseif command == 'vsplit' then
      vim.cmd [[:vert sbuffer %]]
    elseif command == 'tabedit' then
      vim.cmd [[:tab sb %]]
    end
    vim.cmd(string.format([[ lua require'octo.commands'.get_%s('%s', '%s') ]], what, repo, selection.value))
  end
end

local function open_preview_buffer(command)
  return function(prompt_bufnr)
    actions.close(prompt_bufnr)
    local preview_bufnr = require "telescope.state".get_global_key("last_preview_bufnr")
    if command == 'edit' then
      vim.cmd(string.format(":buffer %d", preview_bufnr))
    elseif command == 'split' then
      vim.cmd(string.format(":sbuffer %d", preview_bufnr))
    elseif command == 'vsplit' then
      vim.cmd(string.format(":vert sbuffer %d", preview_bufnr))
    elseif command == 'tabedit' then
      vim.cmd(string.format(":tab sb %d", preview_bufnr))
    end
    vim.cmd [[stopinsert]]
  end
end

local function open_in_browser(type, repo)
  return function(prompt_bufnr)
    local selection = actions.get_selected_entry(prompt_bufnr)
    local number = selection.value
    actions.close(prompt_bufnr)
    util.open_in_browser(type, repo, number)
  end
end

--
-- ISSUES
--

local issue_previewer =
  defaulter(
  function(opts)
    return previewers.new_buffer_previewer {
      get_buffer_by_name = function(_, entry)
        return entry.value
      end,
      define_preview = function(self, entry)
        local bufnr = self.state.bufnr
        if self.state.bufname ~= entry.value or api.nvim_buf_line_count(bufnr) == 1 then
          local number = entry.issue.number
          local owner = vim.split(opts.repo, "/")[1]
          local name = vim.split(opts.repo, "/")[2]
          local query = format(graphql.issue_query, owner, name, number)
          gh.run(
            {
              args = {"api", "graphql", "-f", format("query=%s", query)},
              cb = function(output, stderr)
                if stderr and not util.is_blank(stderr) then
                  api.nvim_err_writeln(stderr)
                elseif output and api.nvim_buf_is_valid(bufnr) then
                  local result = json.parse(output)
                  local issue = result.data.repository.issue
                  writers.write_title(bufnr, issue.title, 1)
                  writers.write_details(bufnr, issue)
                  writers.write_body(bufnr, issue)
                  writers.write_state(bufnr, issue.state:upper(), number)
                  --writers.write_reactions(bufnr, issue.reactions, api.nvim_buf_line_count(bufnr) - 1)
                  api.nvim_buf_set_option(bufnr, "filetype", "octo_issue")
                end
              end
            }
          )
        end
      end
    }
  end
)

local function gen_from_issue(max_number)
  local make_display = function(entry)
    if not entry then
      return nil
    end

    local columns = {
      {entry.issue.number, "TelescopeResultsNumber"},
      {entry.issue.title}
    }

    local displayer =
      entry_display.create {
      separator = " ",
      items = {
        {width = max_number},
        {remaining = true}
      }
    }

    return displayer(columns)
  end

  return function(issue)
    if not issue or vim.tbl_isempty(issue) then
      return nil
    end

    return {
      value = issue.number,
      ordinal = issue.number .. " " .. issue.title,
      display = make_display,
      issue = issue
    }
  end
end

function M.issues(opts)
  opts = opts or {}
  local filter = get_filter(opts, "issue")

  if not opts.repo or opts.repo == vim.NIL then
    opts.repo = util.get_remote_name()
  end
  if not opts.repo then
    api.nvim_err_writeln("Cannot find repo")
    return
  end

  local owner = vim.split(opts.repo, "/")[1]
  local name = vim.split(opts.repo, "/")[2]
  local query = format(graphql.issues_query, owner, name, filter)
  print("Fetching issues (this may take a while) ...")
  gh.run(
    {
      args = {"api", "graphql", "--paginate", "-f", format("query=%s", query)},
      cb = function(output, stderr)
        if stderr and not util.is_blank(stderr) then
          api.nvim_err_writeln(stderr)
        elseif output then
          print(" ")
          local resp = util.aggregate_pages(output, "data.repository.issues.nodes")
          local issues = resp.data.repository.issues.nodes
          if #issues == 0 then
            api.nvim_err_writeln(format("There are no matching issues in %s.", opts.repo))
            return
          end
          local max_number = -1
          for _, issue in ipairs(issues) do
            if #tostring(issue.number) > max_number then
              max_number = #tostring(issue.number)
            end
          end

          pickers.new(
            opts,
            {
              prompt_prefix = "Issues >",
              finder = finders.new_table {
                results = issues,
                entry_maker = gen_from_issue(max_number)
              },
              sorter = conf.generic_sorter(opts),
              previewer = issue_previewer.new(opts),
              attach_mappings = function(_, map)
                actions.goto_file_selection_edit:replace(open(opts.repo, "issue", "edit"))
                actions.goto_file_selection_split:replace(open(opts.repo, "issue", "split"))
                actions.goto_file_selection_vsplit:replace(open(opts.repo, "issue", "vsplit"))
                actions.goto_file_selection_tabedit:replace(open(opts.repo, "issue", "tabedit"))
                map("i", "<c-b>", open_in_browser("issue", opts.repo))
                return true
              end
            }
          ):find()
        end
      end
    }
  )
end

--
-- GISTS
--

local gist_previewer =
  defaulter(
  function(opts)
    return previewers.new_termopen_previewer {
      get_command = opts.get_command or function(entry)
          local tmp_table = vim.split(entry.value, "\t")
          if vim.tbl_isempty(tmp_table) then
            return {"echo", ""}
          end
          local result = {"gh", "gist", "view", tmp_table[1], "|"}
          if vim.fn.executable("bat") then
            table.insert(result, {"bat", "--style=plain", "--color=always", "--paging=always", "--decorations=never", "--pager=less"})
          else
            table.insert(result, "less")
          end
          return flatten(result)
        end
    }
  end,
  {}
)

local function open_gist(prompt_bufnr)
  local selection = actions.get_selected_entry(prompt_bufnr)
  actions.close(prompt_bufnr)
  local tmp_table = vim.split(selection.value, "\t")
  if vim.tbl_isempty(tmp_table) then
    return
  end
  local gist_id = tmp_table[1]
  local gist = utils.get_os_command_output({"gh", "gist", "view",  gist_id, "-r"})
  if gist and vim.api.nvim_buf_get_option(vim.api.nvim_get_current_buf(), "modifiable") then
    api.nvim_put(gist, "b", true, true)
  end
end

function M.gists(opts)
  opts = opts or {}
  opts.limit = opts.limit or 100
  local cmd = {"gh", "gist", "list", "--limit", opts.limit}
  if opts.public then
    table.insert(cmd, "--public")
  end
  if opts.secret then
    table.insert(cmd, "--secret")
  end
  local output = utils.get_os_command_output(cmd)
  if not output or #output == 0 then
    api.nvim_err_writeln("No gists found")
    return
  end

  -- TODO: make a decent displayer
 
  pickers.new(
    opts,
    {
      prompt_prefix = "Gists >",
      finder = finders.new_table {
        results = output,
        entry_maker = make_entry.gen_from_string(opts)
      },
      previewer = gist_previewer.new(opts),
      sorter = conf.generic_sorter(opts),
      attach_mappings = function(_, map)
        map("i", "<CR>", open_gist)
        map("i", "<c-b>", open_in_browser("gist"))
        return true
      end
    }
  ):find()
end

--
-- PULL REQUESTS
--

local function checkout_pull_request(repo)
  return function(prompt_bufnr)
    local selection = actions.get_selected_entry(prompt_bufnr)
    actions.close(prompt_bufnr)
    local tmp_table = vim.split(selection.value, "\t")
    if vim.tbl_isempty(tmp_table) then
      return
    end
    local number = tmp_table[1]
    local args = {"pr", "checkout", number, "-R", repo}
    if repo == "" then
      args = {"pr", "checkout", number}
    end
    gh.run(
      {
        args = args,
        cb = function(output)
          print(output)
          print(format("Checked out PR %d", number))
        end
      }
    )
  end
end

local pull_request_previewer =
  defaulter(
  function(opts)
    return previewers.new_buffer_previewer {
      get_buffer_by_name = function(_, entry)
        return entry.value
      end,
      define_preview = function(self, entry)
        local bufnr = self.state.bufnr
        if self.state.bufname ~= entry.value or api.nvim_buf_line_count(bufnr) == 1 then
          local number = entry.pull_request.number
          local owner = vim.split(opts.repo, "/")[1]
          local name = vim.split(opts.repo, "/")[2]
          local query = format(graphql.pull_request_query, owner, name, number)
          gh.run(
            {
              args = {"api", "graphql", "-f", format("query=%s", query)},
              cb = function(output, stderr)
                if stderr and not util.is_blank(stderr) then
                  api.nvim_err_writeln(stderr)
                elseif output and api.nvim_buf_is_valid(bufnr) then
                  local result = json.parse(output)
                  local pull_request = result.data.repository.pullRequest
                  writers.write_title(bufnr, pull_request.title, 1)
                  writers.write_details(bufnr, pull_request)
                  writers.write_body(bufnr, pull_request)
                  writers.write_state(bufnr, pull_request.state:upper(), number)
                  writers.write_reactions(
                    bufnr,
                    pull_request.reactions,
                    api.nvim_buf_line_count(bufnr) - 1
                  )
                  api.nvim_buf_set_option(bufnr, "filetype", "octo_issue")
                end
              end
            }
          )
        end
      end
    }
  end
)

local function gen_from_pull_request(max_number)
  local make_display = function(entry)
    if not entry then
      return nil
    end

    local columns = {
      {entry.pull_request.number, "TelescopeResultsNumber"},
      {entry.pull_request.title}
    }

    local displayer =
      entry_display.create {
      separator = " ",
      items = {
        {width = max_number},
        {remaining = true}
      }
    }

    return displayer(columns)
  end

  return function(pull_request)
    if not pull_request or vim.tbl_isempty(pull_request) then
      return nil
    end

    return {
      value = pull_request.number,
      ordinal = pull_request.number .. " " .. pull_request.title,
      display = make_display,
      pull_request = pull_request
    }
  end
end

function M.pull_requests(opts)
  opts = opts or {}
  local filter = get_filter(opts, "pull_request")

  if not opts.repo or opts.repo == vim.NIL then
    opts.repo = util.get_remote_name()
  end
  if not opts.repo then
    api.nvim_err_writeln("Cannot find repo")
    return
  end

  local owner = vim.split(opts.repo, "/")[1]
  local name = vim.split(opts.repo, "/")[2]
  local query = format(graphql.pull_requests_query, owner, name, filter)
  print("Fetching issues (this may take a while) ...")
  gh.run(
    {
      args = {"api", "graphql", "--paginate", "-f", format("query=%s", query)},
      cb = function(output, stderr)
        if stderr and not util.is_blank(stderr) then
          api.nvim_err_writeln(stderr)
        elseif output then
          print(" ")
          local resp = util.aggregate_pages(output, "data.repository.pullRequests.nodes")
          local pull_requests = resp.data.repository.pullRequests.nodes
          if #pull_requests == 0 then
            api.nvim_err_writeln(format("There are no matching pull requests in %s.", opts.repo))
            return
          end
          local max_number = -1
          for _, pull in ipairs(pull_requests) do
            if #tostring(pull.number) > max_number then
              max_number = #tostring(pull.number)
            end
          end

          pickers.new(
            opts,
            {
              prompt_prefix = "Pull Requests >",
              finder = finders.new_table {
                results = pull_requests,
                entry_maker = gen_from_pull_request(max_number)
              },
              sorter = conf.generic_sorter(opts),
              previewer = pull_request_previewer.new(opts),
              attach_mappings = function(_, map)
                actions.goto_file_selection_edit:replace(open(opts.repo, "pull_request", "edit"))
                actions.goto_file_selection_split:replace(open(opts.repo, "pull_request", "split"))
                actions.goto_file_selection_vsplit:replace(open(opts.repo, "pull_request", "vsplit"))
                actions.goto_file_selection_tabedit:replace(open(opts.repo, "pull_request", "tabedit"))
                map("i", "<c-o>", checkout_pull_request(opts.repo))
                map("i", "<c-b>", open_in_browser("pr", opts.repo))
                return true
              end
            }
          ):find()
        end
      end
    }
  )
end

--
-- COMMITS
--

local function gen_from_git_commits()
  local displayer =
    entry_display.create {
    separator = " ",
    items = {
      {width = 8},
      {remaining = true}
    }
  }

  local make_display = function(entry)
    return displayer {
      {entry.value:sub(1, 7), "TelescopeResultsNumber"},
      vim.split(entry.msg, "\n")[1]
    }
  end

  return function(entry)
    if not entry then
      return nil
    end

    return {
      value = entry.sha,
      ordinal = entry.sha .. " " .. entry.commit.message,
      msg = entry.commit.message,
      display = make_display,
      author = format("%s <%s>", entry.commit.author.name, entry.commit.author.email),
      date = entry.commit.author.date
    }
  end
end

local commit_previewer =
  defaulter(
  function(opts)
    return previewers.new_buffer_previewer {
      keep_last_buf = true,
      get_buffer_by_name = function(_, entry)
        return entry.value
      end,
      define_preview = function(self, entry)
        if self.state.bufname ~= entry.value or api.nvim_buf_line_count(self.state.bufnr) == 1 then
          local lines = {}
          vim.list_extend(lines, {format("Commit: %s", entry.value)})
          vim.list_extend(lines, {format("Author: %s", entry.author)})
          vim.list_extend(lines, {format("Date: %s", entry.date)})
          vim.list_extend(lines, {""})
          vim.list_extend(lines, vim.split(entry.msg, "\n"))
          vim.list_extend(lines, {""})
          api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)

          local url = format("/repos/%s/commits/%s", opts.repo, entry.value)
          putils.job_maker(
            {"gh", "api", url, "-H", "Accept: application/vnd.github.v3.diff"},
            self.state.bufnr,
            {
              value = entry.value,
              bufname = self.state.bufname,
              mode = "append",
              callback = function(bufnr, _)
                api.nvim_buf_set_option(bufnr, "filetype", "diff")
                api.nvim_buf_add_highlight(bufnr, -1, "OctoNvimDetailsLabel", 0, 0, string.len("Commit:"))
                api.nvim_buf_add_highlight(bufnr, -1, "OctoNvimDetailsLabel", 1, 0, string.len("Author:"))
                api.nvim_buf_add_highlight(bufnr, -1, "OctoNvimDetailsLabel", 2, 0, string.len("Date:"))
              end
            }
          )
        end
      end
    }
  end,
  {}
)

function M.commits()
  local repo, number, _ = util.get_repo_number_pr()
  if not repo then
    return
  end
  -- TODO: graphql
  local url = format("repos/%s/pulls/%d/commits", repo, number)
  gh.run(
    {
      args = {"api", url},
      cb = function(output, stderr)
        if stderr and not util.is_blank(stderr) then
          api.nvim_err_writeln(stderr)
        elseif output then
          local results = json.parse(output)
          pickers.new(
            {},
            {
              prompt_prefix = "PR Commits >",
              finder = finders.new_table {
                results = results,
                entry_maker = gen_from_git_commits()
              },
              sorter = conf.generic_sorter({}),
              previewer = commit_previewer.new({repo = repo}),
              attach_mappings = function()
                actions.goto_file_selection_edit:replace(open_preview_buffer("edit"))
                actions.goto_file_selection_split:replace(open_preview_buffer("split"))
                actions.goto_file_selection_vsplit:replace(open_preview_buffer("vsplit"))
                actions.goto_file_selection_tabedit:replace(open_preview_buffer("tabedit"))
                return true
              end
            }
          ):find()
        end
      end
    }
  )
end

--
-- FILES
--

local function gen_from_git_changed_files()
  local displayer =
    entry_display.create {
    separator = " ",
    items = {
      {width = 8},
      {width = string.len("modified")},
      {width = 5},
      {width = 5},
      {remaining = true}
    }
  }

  local make_display = function(entry)
    return displayer {
      {entry.value:sub(1, 7), "TelescopeResultsNumber"},
      {entry.change.status, "OctoNvimDetailsLabel"},
      {format("+%d", entry.change.additions), "OctoNvimPullAdditions"},
      {format("-%d", entry.change.deletions), "OctoNvimPullDeletions"},
      vim.split(entry.msg, "\n")[1]
    }
  end

  return function(entry)
    if not entry then
      return nil
    end

    return {
      value = entry.sha,
      ordinal = entry.sha .. " " .. entry.filename,
      msg = entry.filename,
      display = make_display,
      change = entry
    }
  end
end

local changed_files_previewer =
  defaulter(
  function()
    return previewers.new_buffer_previewer {
      keep_last_buf = true,
      get_buffer_by_name = function(_, entry)
        return entry.value
      end,
      define_preview = function(self, entry)
        if self.state.bufname ~= entry.value or api.nvim_buf_line_count(self.state.bufnr) == 1 then
          local diff = entry.change.patch
          api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, vim.split(diff, "\n"))
          api.nvim_buf_set_option(self.state.bufnr, "filetype", "diff")
        end
      end
    }
  end,
  {}
)

function M.changed_files()
  local repo, number, _ = util.get_repo_number_pr()
  if not repo then
    return
  end
  -- TODO: graphql
  local url = format("repos/%s/pulls/%d/files", repo, number)
  gh.run(
    {
      args = {"api", url},
      cb = function(output, stderr)
        if stderr and not util.is_blank(stderr) then
          api.nvim_err_writeln(stderr)
        elseif output then
          local results = json.parse(output)
          pickers.new(
            {},
            {
              prompt_prefix = "PR Files Changed >",
              finder = finders.new_table {
                results = results,
                entry_maker = gen_from_git_changed_files()
              },
              sorter = conf.generic_sorter({}),
              previewer = changed_files_previewer.new({repo = repo, number = number}),
              attach_mappings = function()
                actions.goto_file_selection_edit:replace(open_preview_buffer("edit"))
                actions.goto_file_selection_split:replace(open_preview_buffer("split"))
                actions.goto_file_selection_vsplit:replace(open_preview_buffer("vsplit"))
                actions.goto_file_selection_tabedit:replace(open_preview_buffer("tabedit"))
                return true
              end
            }
          ):find()
        end
      end
    }
  )
end

---
-- SEARCH
---

function M.issue_search(opts)
  opts = opts or {}

  if not opts.repo or opts.repo == vim.NIL then
    opts.repo = util.get_remote_name()
  end
  if not opts.repo then
    api.nvim_err_writeln("Cannot find repo")
    return
  end

  local queue = {}
  pickers.new(
    opts,
    {
      prompt_prefix = "Issue Search >",
      finder = function(prompt, process_result, process_complete)
        if not prompt or prompt == "" then
          return nil
        end
        prompt = util.escape_chars(prompt)

        -- skip requests for empty prompts
        if util.is_blank(prompt) then
          process_complete()
          return
        end

        -- store prompt in request queue
        table.insert(queue, prompt)

        -- defer api call so that finder finishes and takes more keystrokes
        vim.defer_fn(function()

          -- do not process response, if this is not the last request we sent
          if prompt ~= queue[#queue] then
            process_complete()
            return
          end

          local query = format(graphql.search_issues_query, opts.repo, prompt)
          gh.run(
            {
              args = {"api", "graphql", "-f", format("query=%s", query)},
              cb = function(output, stderr)

                -- do not process response, if this is not the last request we sent
                if prompt ~= queue[#queue] then
                  process_complete()
                  return
                end

                if stderr and not util.is_blank(stderr) then
                  api.nvim_err_writeln(stderr)
                elseif output then
                  local resp = json.parse(output)
                  for _, issue in ipairs(resp.data.search.nodes) do
                    process_result(gen_from_issue(6)(issue))
                  end
                  process_complete()
                end
              end
            }
          )
        end, 500)
      end,
      sorter = conf.generic_sorter(opts),
      previewer = issue_previewer.new(opts),
      attach_mappings = function(_, map)
        actions.goto_file_selection_edit:replace(open(opts.repo, "issue", "edit"))
        actions.goto_file_selection_split:replace(open(opts.repo, "issue", "split"))
        actions.goto_file_selection_vsplit:replace(open(opts.repo, "issue", "vsplit"))
        actions.goto_file_selection_tabedit:replace(open(opts.repo, "issue", "tabedit"))
        map("i", "<c-b>", open_in_browser("issue", opts.repo))
        return true
      end
    }
  ):find()
end

function M.pull_request_search(opts)
  opts = opts or {}

  if not opts.repo or opts.repo == vim.NIL then
    opts.repo = util.get_remote_name()
  end
  if not opts.repo then
    api.nvim_err_writeln("Cannot find repo")
    return
  end

  local queue = {}
  pickers.new(
    opts,
    {
      prompt_prefix = "PR Search >",
      finder = function(prompt, process_result, process_complete)
        if not prompt or prompt == "" then
          return nil
        end
        prompt = util.escape_chars(prompt)

        -- skip requests for empty prompts
        if util.is_blank(prompt) then
          process_complete()
          return
        end

        -- store prompt in request queue
        table.insert(queue, prompt)

        -- defer api call so that finder finishes and takes more keystrokes
        vim.defer_fn(function()

          -- do not process response, if this is not the last request we sent
          if prompt ~= queue[#queue] then
            process_complete()
            return
          end

          local query = format(graphql.search_pull_requests_query, opts.repo, prompt)
          gh.run(
            {
              args = {"api", "graphql", "-f", format("query=%s", query)},
              cb = function(output, stderr)

                -- do not process response, if this is not the last request we sent
                if prompt ~= queue[#queue] then
                  process_complete()
                  return
                end

                if stderr and not util.is_blank(stderr) then
                  api.nvim_err_writeln(stderr)
                elseif output then
                  local resp = json.parse(output)
                  for _, pull_request in ipairs(resp.data.search.nodes) do
                    process_result(gen_from_pull_request(6)(pull_request))
                  end
                  process_complete()
                end
              end
            }
          )
        end, 500)
      end,
      sorter = conf.generic_sorter(opts),
      previewer = pull_request_previewer.new(opts),
      attach_mappings = function(_, map)
        actions.goto_file_selection_edit:replace(open(opts.repo, "pull_request", "edit"))
        actions.goto_file_selection_split:replace(open(opts.repo, "pull_request", "split"))
        actions.goto_file_selection_vsplit:replace(open(opts.repo, "pull_request", "vsplit"))
        actions.goto_file_selection_tabedit:replace(open(opts.repo, "pull_request", "tabedit"))
        map("i", "<c-b>", open_in_browser("pr", opts.repo))
        return true
      end
    }
  ):find()
end

---
-- REVIEW COMMENTS
---
local function gen_from_review_comment(linenr_length)
  local make_display = function(entry)
    if not entry then
      return nil
    end

    local columns = {
      {entry.comment.path, "TelescopeResultsNumber"},
      {entry.comment.side},
      {entry.comment.line1},
      {entry.comment.line2}
    }

    local displayer =
      entry_display.create {
      separator = " ",
      items = {
        {remaining = true},
        {width = 5},
        {width = linenr_length},
        {width = linenr_length}
      }
    }

    return displayer(columns)
  end

  return function(comment)
    if not comment or vim.tbl_isempty(comment) then
      return nil
    end

    return {
      value = comment.key,
      ordinal = comment.key,
      display = make_display,
      comment = comment
    }
  end
end

local review_comment_previewer =
  defaulter(
  function()
    return previewers.new_buffer_previewer {
      get_buffer_by_name = function(_, entry)
        return entry.value
      end,
      define_preview = function(self, entry)
        local bufnr = self.state.bufnr
        if self.state.bufname ~= entry.value or api.nvim_buf_line_count(bufnr) == 1 then
          -- TODO: pretty print
          writers.write_diff_hunk(bufnr, entry.comment.diff_hunk)
          api.nvim_buf_set_lines(bufnr, -1, -1, false, vim.split(entry.comment.body, "\n"))
        end
      end
    }
  end,
  {}
)

function M.review_comments()
  local comments = vim.tbl_values(reviews.review_comments)
  local max_linenr_length = -1
  for _, comment in ipairs(comments) do
    max_linenr_length = math.max(max_linenr_length, #tostring(comment.line1))
    max_linenr_length = math.max(max_linenr_length, #tostring(comment.line2))
  end
  pickers.new(
    {},
    {
      prompt_prefix = "Review Comments >",
      finder = finders.new_table {
        results = comments,
        entry_maker = gen_from_review_comment(max_linenr_length)
      },
      sorter = conf.generic_sorter({}),
      previewer = review_comment_previewer.new({}),
      attach_mappings = function()
        -- TODO: delete comment
        actions.goto_file_selection_edit:replace(function(prompt_bufnr)
          local comment = actions.get_selected_entry(prompt_bufnr).comment
          actions.close(prompt_bufnr)

          -- select qf item
		      vim.fn.setqflist({}, 'r', {idx = comment.qf_idx })
          reviews.diff_changes_qf_entry()

          -- move cursor to comment line
          local wins = api.nvim_tabpage_list_wins(0)
          local diff_winid = -1
          for _, win in ipairs(wins) do
            if comment.comment_bufnr == api.nvim_win_get_buf(win) then
              diff_winid = win
              break
            end
          end
          if diff_winid > -1 then
            api.nvim_win_set_cursor(diff_winid, {comment.line1, 1})
          end

          -- show comment win/buf
          if comment.comment_winid and api.nvim_win_is_valid(comment.comment_winid) then
            api.nvim_win_set_buf(comment.comment_winid, comment.comment_bufnr)
            api.nvim_set_current_win(comment.comment_winid)
          else
            -- move to qf win
            api.nvim_set_current_win(comment.qf_winid)

            -- create new win and show comment bufnr
            vim.cmd(format("rightbelow vert sbuffer %d", comment.comment_bufnr))
          end
        end)
        return true
      end
    }
  ):find()
end

---
-- PROJECTS
---
local function gen_from_project()
  local make_display = function(entry)
    if not entry then
      return nil
    end

    local columns = {
      {entry.project.name}
    }

    local displayer =
      entry_display.create {
      separator = " ",
      items = {
        {remaining = true}
      }
    }

    return displayer(columns)
  end

  return function(project)
    if not project or vim.tbl_isempty(project) then
      return nil
    end

    return {
      value = project.id,
      ordinal = project.id.. " " .. project.name,
      display = make_display,
      project = project
    }
  end
end

local function gen_from_project_column()
  local make_display = function(entry)
    if not entry then
      return nil
    end

    local columns = {
      {entry.column.name}
    }

    local displayer =
      entry_display.create {
      separator = " ",
      items = {
        {remaining = true}
      }
    }

    return displayer(columns)
  end

  return function(column)
    if not column or vim.tbl_isempty(column) then
      return nil
    end

    return {
      value = column.id,
      ordinal = column.id.. " " .. column.name,
      display = make_display,
      column = column
    }
  end
end

local function gen_from_project_card()
  local make_display = function(entry)
    if not entry then
      return nil
    end

    local columns = {
      {entry.card.column.name},
      {format(" (%s)", entry.card.project.name), "OctoNvimDetailsValue"},
    }

    local displayer =
      entry_display.create {
      separator = " ",
      items = {
        {width = 5},
        {remaining = true}
      }
    }

    return displayer(columns)
  end

  return function(card)
    if not card or vim.tbl_isempty(card) then
      return nil
    end

    return {
      value = card.id,
      ordinal = card.project.name .. " " .. card.column.name,
      display = make_display,
      card = card
    }
  end
end

function M.select_project_card(cb)
  local opts = vim.deepcopy(dropdown_opts)
  local ok, cards = pcall(api.nvim_buf_get_var, 0, "cards")
  if not ok or not cards or #cards.nodes == 0 then
    api.nvim_err_writeln("Cant find any project cards")
    return
  end

  if #cards.nodes == 1 then
    cb(cards.nodes[1].id)
  else
    pickers.new(
      opts,
      {
        prompt_prefix = "Choose card >",
        finder = finders.new_table {
          results = cards.nodes,
          entry_maker = gen_from_project_card()
        },
        sorter = conf.generic_sorter(opts),
        attach_mappings = function(_, _)
          actions.goto_file_selection_edit:replace(function(prompt_bufnr)
            local source_card = actions.get_selected_entry(prompt_bufnr)
            actions.close(prompt_bufnr)
            cb(source_card.card.id)
          end)
          return true
        end
      }
    ):find()
  end
end

function M.select_target_project_column(cb)
  local opts = vim.deepcopy(dropdown_opts)

  local repo = util.get_repo_number()
  if not repo then
    return
  end

  local owner = vim.split(repo, "/")[1]
  local name = vim.split(repo, "/")[2]

  local query = format(graphql.projects_query, owner, name, vim.g.octo_loggedin_user, owner)
  gh.run(
    {
      args = {"api", "graphql", "--paginate", "-f", format("query=%s", query)},
      cb = function(output)
        if output then
          local resp = json.parse(output)
          local projects = {}
          local user_projects = resp.data.user and resp.data.user.projects.nodes or {}
          local repo_projects = resp.data.repository and resp.data.repository.projects.nodes or {}
          local org_projects = not resp.errors and resp.data.organization.projects.nodes or {}
          vim.list_extend(projects, repo_projects)
          vim.list_extend(projects, user_projects)
          vim.list_extend(projects, org_projects)
          if #projects == 0 then
            api.nvim_err_writeln(format("There are no matching projects for %s.", repo))
            return
          end

          pickers.new(
            opts,
            {
              prompt_prefix = "Choose target project >",
              finder = finders.new_table {
                results = projects,
                entry_maker = gen_from_project()
              },
              sorter = conf.generic_sorter(opts),
              attach_mappings = function(_, _)
                actions.goto_file_selection_edit:replace(function(prompt_bufnr)
                  local selected_project = actions.get_selected_entry(prompt_bufnr)
                  actions.close(prompt_bufnr)
                  local opts2 = vim.deepcopy(dropdown_opts)
                  pickers.new(
                    opts2,
                    {
                      prompt_prefix = "Choose target column >",
                      finder = finders.new_table {
                        results = selected_project.project.columns.nodes,
                        entry_maker = gen_from_project_column()
                      },
                      sorter = conf.generic_sorter(opts2),
                      attach_mappings = function()
                        actions.goto_file_selection_edit:replace(function(prompt_bufnr)
                          actions.close(prompt_bufnr)
                          local selected_column = actions.get_selected_entry(prompt_bufnr)
                          cb(selected_column.column.id)
                        end)
                        return true
                      end
                    }
                  ):find()
                end)
                return true
              end
            }
          ):find()
        end
      end
    }
  )
end

local function gen_from_label()
  local make_display = function(entry)
    if not entry then
      return nil
    end

    local columns = {
      {"", hl.create_highlight(entry.label.color, {mode = "foreground"})},
      {entry.label.name, hl.create_highlight(entry.label.color, {})},
      {"", hl.create_highlight(entry.label.color, {mode = "foreground"})}
    }

    local displayer =
      entry_display.create {
      separator = "",
      items = {
        {width = 1},
        {remaining = true},
        {width = 1}
      }
    }

    return displayer(columns)
  end

  return function(label)
    if not label or vim.tbl_isempty(label) then
      return nil
    end

    return {
      value = label.id,
      ordinal = label.name,
      display = make_display,
      label = label
    }
  end
end

function M.select_label(cb)
  local opts = vim.deepcopy(dropdown_opts)
  local repo = util.get_repo_number()
  if not repo then
    return
  end

  local owner = vim.split(repo, "/")[1]
  local name = vim.split(repo, "/")[2]
  local query = format(graphql.labels_query, owner, name)
  gh.run(
    {
      args = {"api", "graphql", "-f", format("query=%s", query)},
      cb = function(output, stderr)
        if stderr and not util.is_blank(stderr) then
          api.nvim_err_writeln(stderr)
        elseif output then
          local resp = json.parse(output)
          local labels = resp.data.repository.labels.nodes
          pickers.new(
            opts,
            {
              prompt_prefix = "Choose label >",
              finder = finders.new_table {
                results = labels,
                entry_maker = gen_from_label()
              },
              sorter = conf.generic_sorter(opts),
              attach_mappings = function(_, _)
                actions.goto_file_selection_edit:replace(function(prompt_bufnr)
                  local selected_label = actions.get_selected_entry(prompt_bufnr)
                  actions.close(prompt_bufnr)
                  cb(selected_label.label.id)
                end)
                return true
              end
            }
          ):find()
        end
      end
    }
  )
end

function M.select_assigned_label(cb)
  local opts = vim.deepcopy(dropdown_opts)
  local repo, number = util.get_repo_number()
  if not repo then
    return
  end
  local bufnr = api.nvim_get_current_buf()
  local bufname = vim.fn.bufname(bufnr)
  local _, type = string.match(bufname, "octo://(.+)/(.+)/(%d+)")
  local owner = vim.split(repo, "/")[1]
  local name = vim.split(repo, "/")[2]
  local query, key
  if type == "issue" then
    query = format(graphql.issue_labels_query, owner, name, number)
    key = "issue"
  elseif type == "pull" then
    query = format(graphql.pull_request_labels_query, owner, name, number)
    key = "pullRequest"
  end
  gh.run(
    {
      args = {"api", "graphql", "-f", format("query=%s", query)},
      cb = function(output, stderr)
        if stderr and not util.is_blank(stderr) then
          api.nvim_err_writeln(stderr)
        elseif output then
          local resp = json.parse(output)
          local labels = resp.data.repository[key].labels.nodes
          pickers.new(
            opts,
            {
              prompt_prefix = "Choose label >",
              finder = finders.new_table {
                results = labels,
                entry_maker = gen_from_label()
              },
              sorter = conf.generic_sorter(opts),
              attach_mappings = function(_, _)
                actions.goto_file_selection_edit:replace(function(prompt_bufnr)
                  local selected_label = actions.get_selected_entry(prompt_bufnr)
                  actions.close(prompt_bufnr)
                  cb(selected_label.label.id)
                end)
                return true
              end
            }
          ):find()
        end
      end
    }
  )
end

local function gen_from_team()
  local make_display = function(entry)
    if not entry then
      return nil
    end

    local columns = {
      {entry.team.name},
    }

    local displayer =
      entry_display.create {
      separator = "",
      items = {
        {remaining = true},
      }
    }

    return displayer(columns)
  end

  return function(team)
    if not team or vim.tbl_isempty(team) then
      return nil
    end

    return {
      value = team.id,
      ordinal = team.name,
      display = make_display,
      team = team
    }
  end
end

function M.select_user(cb)
  local opts = vim.deepcopy(dropdown_opts)
  opts.results_height = 35;

  local queue = {}
  pickers.new(
    opts,
    {
      prompt_prefix = "User Search >",
      finder = function(prompt, process_result, process_complete)
        if not prompt or prompt == "" then
          return nil
        end
        prompt = "repos:>10 " .. util.escape_chars(prompt)

        -- skip requests for empty prompts
        if util.is_blank(prompt) then
          process_complete()
          return
        end

        -- store prompt in request queue
        table.insert(queue, prompt)

        -- defer api call so that finder finishes and takes more keystrokes
        vim.defer_fn(function()

          -- do not process response, if this is not the last request we sent
          if prompt ~= queue[#queue] then
            process_complete()
            return
          end

          local query = format(graphql.user_query, prompt, prompt)
          gh.run(
            {
              args = {"api", "graphql", "--paginate", "-f", format("query=%s", query)},
              cb = function(output, stderr)
                if stderr and not util.is_blank(stderr) then
                  api.nvim_err_writeln(stderr)
                elseif output then
                  -- do not process response, if this is not the last request we sent
                  if prompt ~= queue[#queue] then
                    process_complete()
                    return
                  end
                  local users = {}
                  local orgs = {}
                  local responses = util.get_pages(output)
                  for _, resp in ipairs(responses) do
                    for _, user in ipairs(resp.data.search.nodes) do
                      if not user.teams then
                        -- regular user
                        if not vim.tbl_contains(vim.tbl_keys(users), user.login) then
                          users[user.login] = {
                            value = user.id,
                            text = user.login,
                            display = user.login,
                            ordinal = user.login,
                          }
                        end
                      elseif user.teams and user.teams.totalCount > 0 then
                        -- organization, collect all teams
                        if not vim.tbl_contains(vim.tbl_keys(orgs), user.login) then
                          orgs[user.login] = {
                            value = user.id,
                            text = user.login,
                            display = user.login,
                            ordinal = user.login,
                            teams = user.teams.nodes
                          }
                        else
                          vim.list_extend(orgs[user.login].teams, user.teams.nodes)
                        end
                      end
                    end
                  end

                  -- process users
                  for _, user in pairs(users) do
                    process_result(user)
                  end

                  -- process orgs with teams
                  for _, org in pairs(orgs) do
                    org.display = format("%s (%d)", org.text, #org.teams)
                    process_result(org)
                  end

                  -- call it done for the day
                  process_complete()
                  return
                end
              end
            }
          )
        end, 500)
      end,
      sorter = sorters.get_fuzzy_file(opts),
      attach_mappings = function()
        actions.goto_file_selection_edit:replace(function(prompt_bufnr)
          local selected_user = actions.get_selected_entry(prompt_bufnr)
          actions.close(prompt_bufnr)
          if not selected_user.teams then
            -- user
            cb(selected_user.value)
          else
            -- organization, pick a team
            pickers.new(
              opts,
              {
                prompt_prefix = "Choose team >",
                finder = finders.new_table {
                  results = selected_user.teams,
                  entry_maker = gen_from_team()
                },
                sorter = conf.generic_sorter(opts),
                attach_mappings = function(_, _)
                  actions.goto_file_selection_edit:replace(function(prompt_bufnr)
                    local selected_team = actions.get_selected_entry(prompt_bufnr)
                    actions.close(prompt_bufnr)
                    cb(selected_team.team.id)
                  end)
                  return true
                end
              }
            ):find()
          end
        end)
        return true
      end
    }
  ):find()
end

return M
