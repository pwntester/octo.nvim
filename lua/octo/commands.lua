local octo = require "octo"
local gh = require "octo.gh"
local util = require "octo.util"
local window = require "octo.window"
local menu = require "octo.menu"
local reviews = require "octo.reviews"
local graphql = require "octo.graphql"
local constants = require "octo.constants"
local writers = require "octo.writers"
local vim = vim
local api = vim.api
local format = string.format
local json = {
  parse = vim.fn.json_decode
}

local M = {}

-- supported commands
local commands = {
  issue = {
    create = function(repo)
      M.create_issue(repo)
    end,
    edit = function(...)
      util.get_issue(...)
    end,
    close = function()
      M.change_state("issue", "CLOSED")
    end,
    reopen = function()
      M.change_state("issue", "OPEN")
    end,
    list = function(repo, ...)
      local opts = M.process_varargs(repo, ...)
      menu.issues(opts)
    end,
    search = function(repo, ...)
      local opts = M.process_varargs(repo, ...)
      menu.issue_search(opts)
    end,
    reload = function()
      M.reload()
    end,
    browser = function()
      util.open_in_browser()
    end
  },
  pr = {
    edit = function(...)
      util.get_pull_request(...)
    end,
    close = function()
      M.change_state("pull", "CLOSED")
    end,
    open = function()
      M.change_state("pull", "OPEN")
    end,
    list = function(repo, ...)
      local opts = M.process_varargs(repo, ...)
      menu.pull_requests(opts)
    end,
    checkout = function()
      M.checkout_pr()
    end,
    commits = function()
      menu.commits()
    end,
    changes = function()
      menu.changed_files()
    end,
    diff = function()
      M.show_pr_diff()
    end,
    merge = function(...)
      M.merge_pr(...)
    end,
    checks = function()
      M.pr_checks()
    end,
    ready = function()
      M.pr_ready_for_review()
    end,
    search = function(repo, ...)
      local opts = M.process_varargs(repo, ...)
      menu.pull_request_search(opts)
    end,
    reload = function()
      M.reload()
    end,
    browser = function()
      util.open_in_browser()
    end
  },
  review = {
    start = function()
      reviews.start_review()
    end,
    comments = function()
      reviews.show_pending_comments()
    end,
    submit = function()
      reviews.submit_review()
    end,
    threads = function()
      reviews.review_threads()
    end,
    resume = function()
      reviews.resume_review()
    end,
    discard = function()
      reviews.discard_review()
    end
  },
  gist = {
    list = function(...)
      local args = table.pack(...)
      local opts = {}
      for i = 1, args.n do
        local kv = vim.split(args[i], "=")
        opts[kv[1]] = kv[2]
      end
      menu.gists(opts)
    end
  },
  thread = {
    resolve = function()
      M.resolve_comment()
    end,
    unresolve = function()
      M.unresolve_comment()
    end
  },
  comment = {
    add = function()
      M.add_comment()
    end,
    delete = function()
      M.delete_comment()
    end,
    edit = function()
      reviews.edit_review_comment()
    end,
  },
  label = {
    add = function()
      M.add_label()
    end,
    delete = function()
      M.delete_label()
    end
  },
  assignee = {
    add = function()
      M.add_user("assignee")
    end,
    delete = function()
      M.remove_assignee()
    end
  },
  reviewer = {
    add = function()
      M.add_user("reviewer")
    end
  },
  reaction = {
    add = function(reaction)
      M.reaction_action("add", reaction)
    end,
    delete = function(reaction)
      M.reaction_action("delete", reaction)
    end
  },
  card = {
    add = function()
      M.add_project_card()
    end,
    move = function()
      M.move_project_card()
    end,
    delete = function()
      M.delete_project_card()
    end
  }
}

function M.process_varargs(repo, ...)
  local args = table.pack(...)
  if not repo then
    repo = util.get_remote_name()
  elseif #vim.split(repo, "/") ~= 2 then
    table.insert(args, repo)
    args.n = args.n + 1
    repo = util.get_remote_name()
  end
  local opts = {}
  for i = 1, args.n do
    local kv = vim.split(args[i], "=")
    opts[kv[1]] = kv[2]
  end
  opts.repo = repo
  return opts
end

function M.octo(object, action, ...)
  local o = commands[object]
  if not o then
    local repo, number, kind = util.parse_url(object)
    if repo and number and kind == "issue" then
      util.get_issue(repo, number)
    elseif repo and number and kind == "pull" then
      util.get_pull_request(repo, number)
    else
      print("Incorrect argument, valid objects are:" .. vim.inspect(vim.tbl_keys(commands)))
      return
    end
  else
    local a = o[action]
    if not a then
      print("Incorrect action, valid actions are:" .. vim.inspect(vim.tbl_keys(o)))
      return
    else
      a(...)
    end
  end
end

function M.add_comment()
  local bufnr = api.nvim_get_current_buf()
  local repo = util.get_repo_number({"octo_issue", "octo_reviewthread"})
  if not repo then
    return
  end

  local kind
  local cursor = api.nvim_win_get_cursor(0)
  local thread_id, _, thread_end_line, first_comment_id = util.get_thread_at_cursor(bufnr, cursor)
  if thread_id then
    kind = "PullRequestReviewComment"
  else
    kind = "IssueComment"
  end

  local comment = {
    createdAt = vim.fn.strftime("%FT%TZ"),
    author = {login = vim.g.octo_loggedin_user},
    body = " ",
    first_comment_id = first_comment_id,
    id = -1,
    state = "PENDING",
    reactionGroups = {
      {
        content = "THUMBS_UP",
        users = {
          totalCount = 0
        }
      },
      {
        content = "THUMBS_DOWN",
        users = {
          totalCount = 0
        }
      },
      {
        content = "LAUGH",
        users = {
          totalCount = 0
        }
      },
      {
        content = "HOORAY",
        users = {
          totalCount = 0
        }
      },
      {
        content = "CONFUSED",
        users = {
          totalCount = 0
        }
      },
      {
        content = "HEART",
        users = {
          totalCount = 0
        }
      },
      {
        content = "ROCKET",
        users = {
          totalCount = 0
        }
      },
      {
        content = "EYES",
        users = {
          totalCount = 0
        }
      }
    }
  }
  if kind == "IssueComment" or vim.bo.ft == "octo_reviewthread" then
    -- just place it at the bottom
    writers.write_comment(bufnr, comment, kind)
    vim.fn.execute("normal! Gkkk")
    vim.fn.execute("startinsert")
  elseif kind == "PullRequestReviewComment" and vim.bo.ft == "octo_issue" then
    api.nvim_buf_set_lines(bufnr, thread_end_line + 1, thread_end_line + 1, false, {"x", "x", "x", "x", "x", "x"})
    writers.write_comment(bufnr, comment, kind, thread_end_line + 2)
    vim.fn.execute(":" .. thread_end_line + 4)
    vim.fn.execute("startinsert")
  end
end

function M.delete_comment()
  local bufnr = api.nvim_get_current_buf()
  local repo, _ = util.get_repo_number({"octo_issue", "octo_reviewthread"})
  if not repo then
    return
  end
  local cursor = api.nvim_win_get_cursor(0)
  local comment, start_line, end_line = util.get_comment_at_cursor(bufnr, cursor)
  if not comment then
    print("The cursor does not seem to be located at any comment")
    return
  end
  local query
  if comment.kind == "IssueComment" then
    query = graphql("delete_issue_comment_mutation", comment.id)
  elseif comment.kind == "PullRequestReviewComment" then
    query = graphql("delete_pull_request_review_comment_mutation", comment.id)
  elseif comment.kind == "PullRequestReview" then
    -- Review top level comments cannot be deleted here
    return
  end
  local choice = vim.fn.confirm("Delete comment?", "&Yes\n&No\n&Cancel", 2)
  if choice == 1 then
    gh.run(
      {
        args = {"api", "graphql", "-f", format("query=%s", query)},
        cb = function(_)
          -- TODO: deleting the last review thread comment, it deletes the whole thread
          -- so diff hunk should not be showed any more
          api.nvim_buf_set_lines(bufnr, start_line - 2, end_line + 1, false, {})
          api.nvim_buf_clear_namespace(bufnr, comment.namespace, 0, -1)
          api.nvim_buf_clear_namespace(bufnr, constants.OCTO_REACTIONS_VT_NS, start_line - 2, end_line + 1)
          api.nvim_buf_del_extmark(bufnr, constants.OCTO_COMMENT_NS, comment.extmark)
          local comments = api.nvim_buf_get_var(bufnr, "comments")
          local updated = {}
          for _, c in ipairs(comments) do
            if c.id ~= comment.id then
              table.insert(updated, c)
            end
          end
          api.nvim_buf_set_var(bufnr, "comments", updated)
        end
      }
    )
  end
end

function M.resolve_comment()
  local bufnr = api.nvim_get_current_buf()
  local repo, _ = util.get_repo_number({"octo_issue", "octo_reviewthread"})
  if not repo then
    return
  end

  local thread_id, thread_line, comment_id
  if vim.bo.ft == "octo_issue" then
    local cursor = api.nvim_win_get_cursor(0)
    thread_id, thread_line = util.get_thread_at_cursor(bufnr, cursor)
  elseif vim.bo.ft == "octo_reviewthread" then
    local bufname = api.nvim_buf_get_name(bufnr)
    thread_id, comment_id = string.match(bufname, "octo://.*/pull/%d+/reviewthread/([^/]+)/comment/(.*)")
  end

  local query = graphql("resolve_review_thread_mutation", thread_id)
  gh.run(
    {
      args = {"api", "graphql", "-f", format("query=%s", query)},
      cb = function(output, stderr)
        if stderr and not util.is_blank(stderr) then
          api.nvim_err_writeln(stderr)
        elseif output then
          local resp = json.parse(output)
          local thread = resp.data.resolveReviewThread.thread
          if thread.isResolved then
            if vim.bo.ft == "octo_issue" then
              -- review thread header
              local start_line = thread.originalStartLine ~= vim.NIL and thread.originalStartLine or thread.originalLine
              local end_line = thread.originalLine
              writers.write_review_thread_header(
                bufnr,
                {
                  path = thread.path,
                  start_line = start_line,
                  end_line = end_line,
                  isOutdated = thread.isOutdated,
                  isResolved = thread.isResolved
                },
                thread_line - 2
              )
              vim.cmd(string.format("%d,%dfoldclose", thread_line, thread_line))
            elseif vim.bo.ft == "octo_reviewthread" then
              local pattern = format("%s/%s", thread_id, comment_id)
              local qf = vim.fn.getqflist({items = 0})
              local items = qf.items
              for _, item in ipairs(items) do
                if item.pattern == pattern then
                  item.text = string.gsub(item.text, "%) ", ") RESOLVED ", 1)
                  break
                end
              end
              vim.fn.setqflist({}, "r", {items = items})
            end
          end
        end
      end
    }
  )
end

function M.unresolve_comment()
  local bufnr = api.nvim_get_current_buf()
  local repo, _ = util.get_repo_number({"octo_issue", "octo_reviewthread"})
  if not repo then
    return
  end

  local thread_id, thread_line, comment_id
  if vim.bo.ft == "octo_issue" then
    local cursor = api.nvim_win_get_cursor(0)
    thread_id, thread_line = util.get_thread_at_cursor(bufnr, cursor)
  elseif vim.bo.ft == "octo_reviewthread" then
    local bufname = api.nvim_buf_get_name(bufnr)
    thread_id, comment_id = string.match(bufname, "octo://.*/pull/%d+/reviewthread/([^/]+)/comment/(.*)")
  end

  local query = graphql("unresolve_review_thread_mutation", thread_id)
  gh.run(
    {
      args = {"api", "graphql", "-f", format("query=%s", query)},
      cb = function(output, stderr)
        if stderr and not util.is_blank(stderr) then
          api.nvim_err_writeln(stderr)
        elseif output then
          local resp = json.parse(output)
          local thread = resp.data.unresolveReviewThread.thread
          if not thread.isResolved then
            if vim.bo.ft == "octo_issue" then
              -- review thread header
              local start_line = thread.originalStartLine ~= vim.NIL and thread.originalStartLine or thread.originalLine
              local end_line = thread.originalLine
              writers.write_review_thread_header(
                bufnr,
                {
                  path = thread.path,
                  start_line = start_line,
                  end_line = end_line,
                  isOutdated = thread.isOutdated,
                  isResolved = thread.isResolved
                },
                thread_line - 2
              )
            elseif vim.bo.ft == "octo_reviewthread" then
              local pattern = format("%s/%s", thread_id, comment_id)
              local qf = vim.fn.getqflist({items = 0})
              local items = qf.items
              for _, item in ipairs(items) do
                if item.pattern == pattern then
                  print("found")
                  item.text = string.gsub(item.text, "RESOLVED", "")
                  break
                end
              end
              vim.fn.setqflist({}, "r", {items = items})
            end
          end
        end
      end
    }
  )
end

function M.change_state(type, state)
  local bufnr = api.nvim_get_current_buf()
  local repo, number = util.get_repo_number({"octo_issue"})
  if not repo then
    return
  end

  if not state then
    api.nvim_err_writeln("Missing argument: state")
    return
  end

  local id = api.nvim_buf_get_var(bufnr, "iid")
  local query
  if type == "issue" then
    query = graphql("update_issue_state_mutation", id, state)
  elseif type == "pull" then
    query = graphql("update_pull_request_state_mutation", id, state)
  end

  gh.run(
    {
      args = {"api", "graphql", "-f", format("query=%s", query)},
      cb = function(output, stderr)
        if stderr and not util.is_blank(stderr) then
          api.nvim_err_writeln(stderr)
        elseif output then
          local resp = json.parse(output)
          local new_state, obj
          if type == "issue" then
            obj = resp.data.updateIssue.issue
            new_state = obj.state
          elseif type == "pull" then
            obj = resp.data.updatePullRequest.pullRequest
            new_state = obj.state
          end
          if state == new_state then
            api.nvim_buf_set_var(bufnr, "state", new_state)
            writers.write_state(bufnr, new_state:upper(), number)
            writers.write_details(bufnr, obj, true)
            print("Issue state changed to: " .. new_state)
          end
        end
      end
    }
  )
end

function M.create_issue(repo)
  if not repo then
    repo = util.get_remote_name()
  end
  if not repo then
    print("Cant find repo name")
    return
  end

  vim.fn.inputsave()
  local title = vim.fn.input("Enter title: ")
  vim.fn.inputrestore()

  local repo_id = util.get_repo_id(repo)
  local query = graphql("create_issue_mutation", repo_id, title, constants.NO_BODY_MSG)
  gh.run(
    {
      args = {"api", "graphql", "-f", format("query=%s", query)},
      cb = function(output, stderr)
        if stderr and not util.is_blank(stderr) then
          api.nvim_err_writeln(stderr)
        elseif output then
          local resp = json.parse(output)
          octo.create_buffer("issue", resp.data.createIssue.issue, repo, true)
          vim.fn.execute("normal! Gkkk")
          vim.fn.execute("startinsert")
        end
      end
    }
  )
end

function M.checkout_pr()
  if not util.in_pr_repo() then
    return
  end
  local repo, number, _ = util.get_repo_number_pr()
  if not repo then
    return
  end
  gh.run(
    {
      args = {"pr", "checkout", number, "-R", repo},
      cb = function(output, stderr)
        if stderr and not util.is_blank(stderr) then
          api.nvim_err_writeln(stderr)
        else
          print(output)
          print(format("Checked out PR %d", number))
        end
      end
    }
  )
end

function M.pr_ready_for_review()
  local repo, number, _ = util.get_repo_number_pr()
  if not repo then
    return
  end
  local bufnr = api.nvim_get_current_buf()
  gh.run(
    {
      args = {"pr", "ready", tostring(number)},
      cb = function(output, stderr)
        print(output, stderr)
        writers.write_state(bufnr)
      end
    }
  )
end

function M.pr_checks()
  local repo, number, _ = util.get_repo_number_pr()
  if not repo then
    return
  end
  gh.run(
    {
      args = {"pr", "checks", tostring(number), "-R", repo},
      cb = function(output, stderr)
        if stderr and not util.is_blank(stderr) then
          api.nvim_err_writeln(stderr)
        elseif output then
          local max_lengths = {}
          local parts = {}
          for _, l in pairs(vim.split(output, "\n")) do
            local line_parts = vim.split(l, "\t")
            for i, p in pairs(line_parts) do
              if max_lengths[i] == nil or max_lengths[i] < #p then
                max_lengths[i] = #p
              end
            end
            table.insert(parts, line_parts)
          end

          local lines = {}
          for _, p in pairs(parts) do
            local line = {}
            for i, pp in pairs(p) do
              table.insert(line, pp .. (" "):rep(max_lengths[i] - #pp))
            end
            table.insert(lines, table.concat(line, "  "))
          end
          local _, bufnr = window.create_centered_float({
            header = "Checks",
            content=lines
          })
          local buf_lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
          for i, l in ipairs(buf_lines) do
            if #vim.split(l, "pass") > 1 then
              api.nvim_buf_add_highlight(bufnr, -1, "OctoNvimPassingTest", i - 1, 0, -1)
            elseif #vim.split(l, "fail") > 1 then
              api.nvim_buf_add_highlight(bufnr, -1, "OctoNvimFailingTest", i - 1, 0, -1)
            end
          end
        end
      end
    }
  )
end

function M.merge_pr(...)
  local repo, number, _ = util.get_repo_number_pr()
  if not repo then
    return
  end
  local args = {"pr", "merge", tostring(number)}
  local params = table.pack(...)
  for i = 1, params.n do
    if params[i] == "delete" then
      table.insert(args, "--delete-branch")
    end
  end
  local has_flag = false
  for i = 1, params.n do
    if params[i] == "commit" then
      table.insert(args, "--merge")
      has_flag = true
    elseif params[i] == "squash" then
      table.insert(args, "--squash")
      has_flag = true
    elseif params[i] == "rebase" then
      table.insert(args, "--rebase")
      has_flag = true
    end
  end
  if not has_flag then
    table.insert(args, "--merge")
  end
  local bufnr = api.nvim_get_current_buf()
  gh.run(
    {
      args = args,
      cb = function(output, stderr)
        print(output, stderr)
        writers.write_state(bufnr)
      end
    }
  )
end

function M.show_pr_diff()
  local repo, number, _ = util.get_repo_number_pr()
  if not repo then
    return
  end
  local url = format("/repos/%s/pulls/%s", repo, number)
  gh.run(
    {
      args = {"api", url},
      headers = {"Accept: application/vnd.github.v3.diff"},
      cb = function(output, stderr)
        if stderr and not util.is_blank(stderr) then
          api.nvim_err_writeln(stderr)
        elseif output then
          local lines = vim.split(output, "\n")
          local bufnr = api.nvim_create_buf(true, true)
          api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
          api.nvim_set_current_buf(bufnr)
          api.nvim_buf_set_option(bufnr, "filetype", "diff")
        end
      end
    }
  )
end

function M.reaction_action(action, reaction)
  local bufnr = api.nvim_get_current_buf()

  reaction = reaction:upper()
  if reaction == "+1" then
    reaction = "THUMBS_UP"
  elseif reaction == "-1" then
    reaction = "THUMBS_DOWN"
  end

  local repo, _ = util.get_repo_number({"octo_issue", "octo_reviewthread"})
  if not repo then
    return
  end

  local cursor = api.nvim_win_get_cursor(0)
  local comment = util.get_comment_at_cursor(bufnr, cursor)

  local query, reaction_line, reaction_groups

  if comment then
    -- found a comment at cursor
    reaction_groups = comment.reaction_groups
    reaction_line = comment.reaction_line

    if action == "add" then
      query = graphql("add_reaction_mutation", comment.id, reaction)
    elseif action == "delete" then
      query = graphql("remove_reaction_mutation", comment.id, reaction)
    end
  elseif vim.bo.ft == "octo_issue" then
    -- cursor not located on a comment, using the issue instead
    reactions = api.nvim_buf_get_var(bufnr, "body_reactions")
    reaction_line = api.nvim_buf_get_var(bufnr, "body_reaction_line")

    local id = api.nvim_buf_get_var(bufnr, "iid")
    if action == "add" then
      query = graphql("add_reaction_mutation", id, reaction)
    elseif action == "delete" then
      query = graphql("remove_reaction_mutation", id, reaction)
    end
  end

  -- add/delete reaction
  gh.run(
    {
      args = {"api", "graphql", "-f", format("query=%s", query)},
      cb = function(output, stderr)
        if stderr and not util.is_blank(stderr) then
          api.nvim_err_writeln(stderr)
        elseif output then
          local resp = json.parse(output)
          if action == "add" then
            reaction_groups = resp.data.addReaction.subject.reactionGroups
          elseif action == "delete" then
            reaction_groups = resp.data.removeReaction.subject.reactionGroups
          end

          -- update comment metadata with new reactions
          util.update_reactions_at_cursor(bufnr, cursor, reaction_groups)

          -- refresh reactions
          writers.write_reactions(bufnr, reaction_groups, reaction_line)
        end
      end
    }
  )
end

function M.command_complete(args)
  local command_keys = vim.tbl_keys(commands)
  local argLead, cmdLine, _ = unpack(args)
  local parts = vim.split(cmdLine, " ")

  local get_options = function(options)
    local valid_options = {}
    for _, option in pairs(options) do
      if string.sub(option, 1, #argLead) == argLead then
        table.insert(valid_options, option)
      end
    end
    return valid_options
  end

  if #parts == 2 then
    return get_options(command_keys)
  elseif #parts == 3 then
    local o = commands[parts[2]]
    if not o then
      return
    end
    return get_options(vim.tbl_keys(o))
  end
end

function M.add_project_card()
  local bufnr = api.nvim_get_current_buf()
  local repo = util.get_repo_number()
  if not repo then
    return
  end

  local iid_ok, iid = pcall(api.nvim_buf_get_var, 0, "iid")
  if not iid_ok or not iid then
    api.nvim_err_writeln("Cannot get issue/pr id")
  end

  -- show column selection menu
  menu.select_target_project_column(
    function(column_id)
      -- add new card
      local query = graphql("add_project_card_mutation", iid, column_id)
      gh.run(
        {
          args = {"api", "graphql", "--paginate", "-f", format("query=%s", query)},
          cb = function(output, stderr)
            if stderr and not util.is_blank(stderr) then
              api.nvim_err_writeln(stderr)
            elseif output then
              -- refresh issue/pr details
              octo.load(
                bufnr,
                function(obj)
                  writers.write_details(bufnr, obj, true)
                  api.nvim_buf_set_var(bufnr, "cards", obj.projectCards)
                end
              )
            end
          end
        }
      )
    end
  )
end

function M.delete_project_card()
  local bufnr = api.nvim_get_current_buf()
  local repo = util.get_repo_number()
  if not repo then
    return
  end

  -- show card selection menu
  menu.select_project_card(
    function(card)
      -- delete card
      local query = graphql("delete_project_card_mutation", card)
      gh.run(
        {
          args = {"api", "graphql", "--paginate", "-f", format("query=%s", query)},
          cb = function(output, stderr)
            if stderr and not util.is_blank(stderr) then
              api.nvim_err_writeln(stderr)
            elseif output then
              -- refresh issue/pr details
              octo.load(
                bufnr,
                function(obj)
                  writers.write_details(bufnr, obj, true)
                  api.nvim_buf_set_var(bufnr, "cards", obj.projectCards)
                end
              )
            end
          end
        }
      )
    end
  )
end

function M.move_project_card()
  local bufnr = api.nvim_get_current_buf()
  local repo = util.get_repo_number()
  if not repo then
    return
  end

  menu.select_project_card(
    function(source_card)
      -- show project column selection menu
      menu.select_target_project_column(
        function(target_column)
          -- move card to selected column
          local query = graphql("move_project_card_mutation", source_card, target_column)
          gh.run(
            {
              args = {"api", "graphql", "--paginate", "-f", format("query=%s", query)},
              cb = function(output, stderr)
                if stderr and not util.is_blank(stderr) then
                  api.nvim_err_writeln(stderr)
                elseif output then
                  -- refresh issue/pr details
                  octo.load(
                    bufnr,
                    function(obj)
                      writers.write_details(bufnr, obj, true)
                      api.nvim_buf_set_var(bufnr, "cards", obj.projectCards)
                    end
                  )
                end
              end
            }
          )
        end
      )
    end
  )
end

function M.reload(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()
  local repo = util.get_repo_number()
  if not repo then
    return
  end
  octo.load_buffer(bufnr)
end

function M.add_label()
  local bufnr = api.nvim_get_current_buf()
  local repo = util.get_repo_number()
  if not repo then
    return
  end

  local iid_ok, iid = pcall(api.nvim_buf_get_var, 0, "iid")
  if not iid_ok or not iid then
    api.nvim_err_writeln("Cannot get issue/pr id")
  end

  menu.select_label(
    function(label_id)
      local query = graphql("add_labels_mutation", iid, label_id)
      gh.run(
        {
          args = {"api", "graphql", "--paginate", "-f", format("query=%s", query)},
          cb = function(output, stderr)
            if stderr and not util.is_blank(stderr) then
              api.nvim_err_writeln(stderr)
            elseif output then
              -- refresh issue/pr details
              octo.load(
                bufnr,
                function(obj)
                  writers.write_details(bufnr, obj, true)
                end
              )
            end
          end
        }
      )
    end
  )
end

function M.delete_label()
  local bufnr = api.nvim_get_current_buf()
  local repo = util.get_repo_number()
  if not repo then
    return
  end

  local iid_ok, iid = pcall(api.nvim_buf_get_var, 0, "iid")
  if not iid_ok or not iid then
    api.nvim_err_writeln("Cannot get issue/pr id")
  end

  menu.select_assigned_label(
    function(label_id)
      local query = graphql("remove_labels_mutation", iid, label_id)
      gh.run(
        {
          args = {"api", "graphql", "--paginate", "-f", format("query=%s", query)},
          cb = function(output, stderr)
            if stderr and not util.is_blank(stderr) then
              api.nvim_err_writeln(stderr)
            elseif output then
              -- refresh issue/pr details
              octo.load(
                bufnr,
                function(obj)
                  writers.write_details(bufnr, obj, true)
                end
              )
            end
          end
        }
      )
    end
  )
end

function M.add_user(subject)
  local bufnr = api.nvim_get_current_buf()
  local repo = util.get_repo_number()
  if not repo then
    return
  end

  local iid_ok, iid = pcall(api.nvim_buf_get_var, 0, "iid")
  if not iid_ok or not iid then
    api.nvim_err_writeln("Cannot get issue/pr id")
  end

  menu.select_user(
    function(user_id)
      local query
      if subject == "assignee" then
        query = graphql("add_assignees_mutation", iid, user_id)
      elseif subject == "reviewer" then
        query = graphql("request_reviews_mutation", iid, user_id)
      end
      gh.run(
        {
          args = {"api", "graphql", "--paginate", "-f", format("query=%s", query)},
          cb = function(output, stderr)
            if stderr and not util.is_blank(stderr) then
              api.nvim_err_writeln(stderr)
            elseif output then
              -- refresh issue/pr details
              octo.load(
                bufnr,
                function(obj)
                  writers.write_details(bufnr, obj, true)
                end
              )
            end
          end
        }
      )
    end
  )
end

function M.remove_assignee()
  local bufnr = api.nvim_get_current_buf()
  local repo = util.get_repo_number()
  if not repo then
    return
  end

  local iid_ok, iid = pcall(api.nvim_buf_get_var, 0, "iid")
  if not iid_ok or not iid then
    api.nvim_err_writeln("Cannot get issue/pr id")
  end

  menu.select_assignee(
    function(user_id)
      local query = graphql("remove_assignees_mutation", iid, user_id)
      gh.run(
        {
          args = {"api", "graphql", "--paginate", "-f", format("query=%s", query)},
          cb = function(output, stderr)
            if stderr and not util.is_blank(stderr) then
              api.nvim_err_writeln(stderr)
            elseif output then
              -- refresh issue/pr details
              octo.load(
                bufnr,
                function(obj)
                  writers.write_details(bufnr, obj, true)
                end
              )
            end
          end
        }
      )
    end
  )
end

return M
