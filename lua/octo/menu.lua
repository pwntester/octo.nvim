local actions = require "telescope.actions"
local finders = require "telescope.finders"
local pickers = require "telescope.pickers"
local utils = require "telescope.utils"
local putils = require "telescope.previewers.utils"
local previewers = require "telescope.previewers"
local conf = require "telescope.config".values
local make_entry = require "telescope.make_entry"
local entry_display = require "telescope.pickers.entry_display"
local writers = require "octo.writers"
local gh = require "octo.gh"
local util = require "octo.util"
local graphql = require "octo.graphql"
local format = string.format
local defaulter = utils.make_default_callable
local vim = vim
local flatten = vim.tbl_flatten
local api = vim.api
local bat_options = {"bat", "--style=plain", "--color=always", "--paging=always", "--decorations=never", "--pager=less"}
local json = {
  parse = vim.fn.json_decode,
  stringify = vim.fn.json_encode
}

local M = {}

local function parse_opts(opts, target)
  local query = {}
  local tmp_table = {}
  if target == "issue" then
    tmp_table = {"author", "assigner", "mention", "label", "milestone", "state", "limit"}
  elseif target == "pr" then
    tmp_table = {"assigner", "label", "state", "base", "limit"}
  elseif target == "gist" then
    tmp_table = {"public", "secret"}
    if opts.public then
      opts.public = " "
    end
    if opts.secret then
      opts.secret = " "
    end
  end

  for _, value in pairs(tmp_table) do
    if opts[value] then
      table.insert(query, format("--%s %s", value, opts[value]))
    end
  end
  return table.concat(query, " ")
end

local function get_filter(opts, kind)
  local filter = ""
  local allowed_values = {}
  if kind == "issue" then
    allowed_values = {"createdBy", "assignee", "mentioned", "labels", "milestone", "states"}
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
    actions.close(prompt_bufnr)
    local tmp_table = vim.split(selection.value, "\t")
    if vim.tbl_isempty(tmp_table) then
      return
    end
    local cmd
    if not repo or repo == "" then
      cmd = format("gh %s view --web %s", type, tmp_table[1])
    else
      cmd = format("gh %s view --web %s -R %s", type, tmp_table[1], repo)
    end
    os.execute(cmd)
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
              prompt_title = "Issues",
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
            table.insert(result, bat_options)
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
  local text = utils.get_os_command_output("gh gist view " .. gist_id .. " -r")
  if text and vim.api.nvim_buf_get_option(vim.api.nvim_get_current_buf(), "modifiable") then
    vim.api.nvim_put(vim.split(text, "\n"), "b", true, true)
  end
end

function M.gists(opts)
  opts = opts or {}
  opts.limit = opts.limit or 100
  local opts_query = parse_opts(opts, "gist")
  local cmd = format("gh gist list %s", opts_query)
  local results = vim.split(utils.get_os_command_output(cmd), "\n")

  pickers.new(
    opts,
    {
      prompt_title = "Gists",
      finder = finders.new_table {
        results = results,
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
          for _, issue in ipairs(pull_requests) do
            if #tostring(issue.number) > max_number then
              max_number = #tostring(issue.number)
            end
          end

          pickers.new(
            opts,
            {
              prompt_title = "Pull Requests",
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
              prompt_title = "PR Commits",
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
      {format("+%d", entry.change.additions), "DiffAdd"},
      {format("-%d", entry.change.deletions), "DiffDelete"},
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
              prompt_title = "PR Files Changed",
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
      prompt_title = "Issue Search",
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
                  process_result(gen_from_issue(4)(issue))
                end
                process_complete()
              end
            end
          }
        )
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
      prompt_title = "PR Search",
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
                  process_result(gen_from_pull_request(4)(pull_request))
                end
                process_complete()
              end
            end
          }
        )
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

return M
