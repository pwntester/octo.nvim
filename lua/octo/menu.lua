local actions = require("telescope.actions")
local finders = require("telescope.finders")
local pickers = require("telescope.pickers")
local utils = require("telescope.utils")
local previewers = require("telescope.previewers")
local conf = require("telescope.config").values
local make_entry = require("telescope.make_entry")
local entry_display = require("telescope.pickers.entry_display")
local putils = require('telescope.previewers.utils')
local from_entry = require('telescope.from_entry')
local gh = require "octo.gh"
local util = require("octo.util")
local format = string.format
local defaulter = utils.make_default_callable
local flatten = vim.tbl_flatten
local api = vim.api
local bat_options = {"bat", "--style=plain", "--color=always", "--paging=always", "--decorations=never", "--pager=less"}
local json = {
  parse = vim.fn.json_decode,
  stringify = vim.fn.json_encode
}

-- most of this code was taken from https://github.com/nvim-telescope/telescope-github.nvim/blob/master/lua/telescope/_extensions/ghcli.lua
-- thanks @windwp!

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

local function open_issue(repo)
  return function(prompt_bufnr)
    local selection = actions.get_selected_entry(prompt_bufnr)
    actions.close(prompt_bufnr)
    local tmp_table = vim.split(selection.value, "\t")
    if vim.tbl_isempty(tmp_table) then
      return
    end
    vim.cmd(string.format([[ lua require'octo.commands'.get_issue('%s', '%s') ]], repo, tmp_table[1]))
  end
end

local function issues(repo, opts)
  opts = opts or {}
  opts.limit = opts.limit or 100
  local opts_query = parse_opts(opts, "issue")
  if not repo or repo == vim.NIL then
    repo = util.get_remote_name()
  end
  if not repo then
    api.nvim_err_writeln("Cannot find repo")
    return
  end
  local cmd = format("gh issue list %s -R %s", opts_query, repo)
  local results = vim.split(utils.get_os_command_output(cmd), "\n")

  if #results == 0 or #results == 1 and results[1] == "" then
    api.nvim_err_writeln(format("There are no matching issues in %s.", repo))
    return
  end

  pickers.new(
    opts,
    {
      prompt_title = "Issues",
      finder = finders.new_table {
        results = results,
        entry_maker = make_entry.gen_from_string(opts)
      },
      sorter = conf.file_sorter(opts),
      previewer = previewers.new_termopen_previewer {
        get_command = function(entry)
          local tmp_table = vim.split(entry.value, "\t")
          if vim.tbl_isempty(tmp_table) then
            return {"echo", ""}
          end
          return {"gh", "issue", "view", tmp_table[1], "-R", repo}
        end
      },
      attach_mappings = function(_, map)
        map("i", "<CR>", open_issue(repo))
        map("i", "<c-t>", open_in_browser("issue", repo))
        return true
      end
    }
  ):find()
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

local function gists(opts)
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
      sorter = conf.file_sorter(opts),
      attach_mappings = function(_, map)
        map("i", "<CR>", open_gist)
        map("i", "<c-t>", open_in_browser("gist"))
        return true
      end
    }
  ):find()
end

--
-- PULL REQUESTS
--

local function checkout_pr(repo)
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

local function pull_requests(repo, opts)
  opts = opts or {}
  opts.limit = opts.limit or 100
  local opts_query = parse_opts(opts, "pr")
  if not repo or repo == vim.NIL then
    repo = util.get_remote_name()
  end
  if not repo then
    print("Cannot find repo")
    return
  end
  local cmd = format("gh pr list %s -R %s", opts_query, repo)
  local results = vim.split(utils.get_os_command_output(cmd), "\n")

  if #results == 0 or #results == 1 and results[1] == "" then
    api.nvim_err_writeln(format("There are no matching pull requests in %s.", repo))
    return
  end

  pickers.new(
    opts,
    {
      prompt_title = "Pull Requests",
      finder = finders.new_table {
        results = results,
        entry_maker = make_entry.gen_from_string(opts)
      },
      previewer = previewers.new_termopen_previewer {
        get_command = function(entry)
          local tmp_table = vim.split(entry.value, "\t")
          if vim.tbl_isempty(tmp_table) then
            return {"echo", ""}
          end
          return {"gh", "pr", "view", tmp_table[1], "-R", repo}
        end
      },
      sorter = conf.file_sorter(opts),
      attach_mappings = function(_, map)
        map("i", "<CR>", open_issue(repo))
        map("i", "<c-o>", checkout_pr(repo))
        map("i", "<c-t>", open_in_browser("pr"))
        return true
      end
    }
  ):find()
end

--
-- COMMITS
--

function gen_from_git_commits()
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
      entry.msg
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
      display = make_display
    }
  end
end

local commit_previewer = defaulter(function(opts)
  return previewers.new_buffer_previewer {
    get_buffer_by_name = function(_, entry)
      return from_entry.path(entry, true)
    end,

    define_preview = function(self, entry, status)
      putils.with_preview_window(status, nil, function()
        local url = format("/repos/%s/commits/%s", opts.repo, entry.value)
        local diff =
          gh.run(
          {
            args = {"api", url},
            mode = "sync",
            headers = {"Accept: application/vnd.github.v3.diff"}
          }
        )
        local lines = {}
        print(vim.inspect(entry))
        vim.list_extend(lines, vim.split(entry.msg, "\n"))
        vim.list_extend(lines, {entry.value})
        vim.list_extend(lines, vim.split(diff, "\n"))
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
        vim.api.nvim_buf_set_option(self.state.bufnr, "filetype", "diff")
      end)
    end
  }
end, {})

local function commits()
  local bufname = api.nvim_buf_get_name(0)
  if not vim.startswith(bufname, "octo://") then
    api.nvim_err_writeln("Not in octo buffer")
    return
  end
  local repo = api.nvim_buf_get_var(0, "repo")
  local number = api.nvim_buf_get_var(0, "number")
  if not repo or not number then
    api.nvim_err_writeln("Cannot find repo or number")
    return
  end
  local status, pr = pcall(api.nvim_buf_get_var, 0, "pr")
  if status and pr then
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
                sorter = conf.file_sorter({}),
                previewer = commit_previewer.new({repo = repo})
                -- attach_mappings = function(_, map)
                --   map("i", "<CR>", open_issue(repo))
                --   map("i", "<c-t>", open_in_browser("issue", repo))
                --   return true
                -- end
              }
            ):find()
          end
        end
      }
    )
  else
    api.nvim_err_writeln("Not in PR buffer")
  end
end

return {
  issues = issues,
  pull_requests = pull_requests,
  gists = gists,
  commits = commits
}
