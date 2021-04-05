local octo = require "octo"
local gh = require "octo.gh"
local util = require "octo.util"
local navigation = require "octo.navigation"
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
      navigation.open_in_browser()
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
      navigation.open_in_browser()
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
      M.resolve_thread()
    end,
    unresolve = function()
      M.unresolve_thread()
    end
  },
  comment = {
    add = function()
      M.add_comment()
    end,
    delete = function()
      M.delete_comment()
    end
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
    thumbs_up = function()
      M.reaction_action("THUMBS_UP")
    end,
    ["+1"] = function()
      M.reaction_action("THUMBS_UP")
    end,
    thumbs_down = function()
      M.reaction_action("THUMBS_DOWN")
    end,
    ["-1"] = function()
      M.reaction_action("THUMBS_DOWN")
    end,
    eyes = function()
      M.reaction_action("EYES")
    end,
    laugh = function()
      M.reaction_action("LAUGH")
    end,
    confused = function()
      M.reaction_action("CONFUSED")
    end,
    hooray = function()
      M.reaction_action("HOORAY")
    end,
    party = function()
      M.reaction_action("HOORAY")
    end,
    tada = function()
      M.reaction_action("HOORAY")
    end,
    rocket = function()
      M.reaction_action("ROCKET")
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
      print("[Octo] Incorrect argument, valid objects are:" .. vim.inspect(vim.tbl_keys(commands)))
      return
    end
  else
    local a = o[action]
    if not a then
      print("[Octo] Incorrect action, valid actions are:" .. vim.inspect(vim.tbl_keys(o)))
      return
    else
      a(...)
    end
  end
end

function M.add_comment()
  local bufnr = api.nvim_get_current_buf()
  local repo = util.get_repo_number({"issue", "pull", "reviewthread"})
  if not repo then return end

  local comment_kind
  local thread_id, _, thread_end_line, replyTo = util.get_thread_at_cursor(bufnr)
  if thread_id then
    comment_kind = "PullRequestReviewComment"
  else
    comment_kind = "IssueComment"
  end

  local kind = util.get_octo_kind(bufnr)
  if comment_kind == "PullRequestReviewComment" and (kind == "issue" or kind == "pull") then
    -- TODO: support adding single-comment reviews from PR buffer
    api.nvim_err_writeln("[Octo] Not yet supported")
    return
  end

  local comment = {
    id = -1,
    author = {login = vim.g.octo_viewer},
    state = "PENDING",
    createdAt = vim.fn.strftime("%FT%TZ"),
    body = " ",
    replyTo = replyTo,
    viewerCanUpdate = true,
    viewerCanDelete = true,
    viewerDidAuthor = true,
    pullRequestReview = { id = reviews.getReviewId() },
    reactionGroups = {
      { content = "THUMBS_UP", users = { totalCount = 0 } },
      { content = "THUMBS_DOWN", users = { totalCount = 0 } },
      { content = "LAUGH", users = { totalCount = 0 } },
      { content = "HOORAY", users = { totalCount = 0 } },
      { content = "CONFUSED", users = { totalCount = 0 } },
      { content = "HEART", users = { totalCount = 0 } },
      { content = "ROCKET", users = { totalCount = 0 } },
      { content = "EYES", users = { totalCount = 0 } }
    }
  }

  if comment_kind == "IssueComment" then
    -- just place it at the bottom
    writers.write_comment(bufnr, comment, comment_kind)
    vim.fn.execute("normal! Gk")
    vim.fn.execute("startinsert")
  elseif comment_kind == "PullRequestReviewComment" then
    api.nvim_buf_set_lines(bufnr, thread_end_line, thread_end_line, false, {"x", "x", "x", "x"})
    writers.write_comment(bufnr, comment, comment_kind, thread_end_line + 1)
    vim.fn.execute(":" .. thread_end_line + 3)
    vim.fn.execute("startinsert")
  end

  -- drop undo history
  vim.fn["octo#clear_history"]()
end

function M.delete_comment()
  local bufnr = api.nvim_get_current_buf()
  local repo = util.get_repo_number({"issue", "pull", "reviewthread"})
  if not repo then return end
  local comment, start_line, end_line = util.get_comment_at_cursor(bufnr)
  if not comment then
    print("[Octo] The cursor does not seem to be located at any comment")
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
        cb = function(output)
          -- TODO: deleting the last review thread comment, it deletes the whole thread
          -- so diff hunk should not be showed any more
          local resp = json.parse(output)
          if comment.kind == "PullRequestReviewComment" then
            local threads = resp.data.deletePullRequestReviewComment.pullRequestReview.pullRequest.reviewThreads.nodes
            require"octo.reviews".update_threads(threads)
          end

          if comment.reaction_line then
            api.nvim_buf_set_lines(bufnr, start_line - 2, end_line + 1, false, {})
            api.nvim_buf_clear_namespace(bufnr, constants.OCTO_REACTIONS_VT_NS, start_line - 2, end_line + 1)
          else
            api.nvim_buf_set_lines(bufnr, start_line - 2, end_line - 1, false, {})
          end
          api.nvim_buf_clear_namespace(bufnr, comment.namespace, 0, -1)
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

function M.resolve_thread()
  local bufnr = api.nvim_get_current_buf()
  local repo = util.get_repo_number({"issue", "pull", "reviewthread"})
  if not repo then return end
  local thread_id, thread_line = util.get_thread_at_cursor(bufnr)
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
            -- review thread header
            local start_line = thread.originalStartLine ~= vim.NIL and thread.originalStartLine or thread.originalLine
            local end_line = thread.originalLine
            writers.write_review_thread_header(
              bufnr, {
                path = thread.path,
                start_line = start_line,
                end_line = end_line,
                isOutdated = thread.isOutdated,
                isResolved = thread.isResolved
              }, thread_line - 2)
            local threads = resp.data.resolveReviewThread.thread.pullRequest.reviewThreads.nodes
print(vim.inspect(threads))
            require"octo.reviews".update_threads(threads)
            --vim.cmd(string.format("%d,%dfoldclose", thread_line, thread_line))
          end
        end
      end
    }
  )
end

function M.unresolve_thread()
  local bufnr = api.nvim_get_current_buf()
  local repo = util.get_repo_number({"issue", "pull", "reviewthread"})
  if not repo then return end
  local thread_id, thread_line = util.get_thread_at_cursor(bufnr)
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
            -- review thread header
            local start_line = thread.originalStartLine ~= vim.NIL and thread.originalStartLine or thread.originalLine
            local end_line = thread.originalLine
            writers.write_review_thread_header(
              bufnr, {
                path = thread.path,
                start_line = start_line,
                end_line = end_line,
                isOutdated = thread.isOutdated,
                isResolved = thread.isResolved
              }, thread_line - 2)
            local threads = resp.data.unresolveReviewThread.thread.pullRequest.reviewThreads.nodes
            require"octo.reviews".update_threads(threads)
          end
        end
      end
    }
  )
end

function M.change_state(type, state)
  local bufnr = api.nvim_get_current_buf()
  local repo, number = util.get_repo_number({"issue", "pull"})
  if not repo then return end

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
            print("[Octo] Issue state changed to: " .. new_state)
          end
        end
      end
    }
  )
end

function M.create_issue(repo)
  if not repo then repo = util.get_remote_name() end
  if not repo then
    print("[Octo] Cant find repo name")
    return
  end

  vim.fn.inputsave()
  local title = vim.fn.input(format("Creating issue in %s. Enter title: ", repo))
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
          vim.fn.execute("normal! Gk")
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
          print("[Octo]", output)
          print(format("[Octo] Checked out PR %d", number))
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
        print("[Octo]", output, stderr)
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
        print("[Octo]", output, stderr)
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

function M.reaction_action(reaction)
  local bufnr = api.nvim_get_current_buf()
  local repo = util.get_repo_number({"issue", "pull", "reviewthread"})
  if not repo then return end
  local kind = util.get_octo_kind(bufnr)

  -- normalize reactions
  reaction = reaction:upper()
  if reaction == "+1" then
    reaction = "THUMBS_UP"
  elseif reaction == "-1" then
    reaction = "THUMBS_DOWN"
  elseif reaction == "PARTY" or reaction == "TADA" then
    reaction = "HOORAY"
  end

  local reaction_line, reaction_groups, insert_line, id, action

  local comment = util.get_comment_at_cursor(bufnr)
  if comment then
    -- found a comment at cursor
    reaction_groups = comment.reaction_groups
    reaction_line = comment.reaction_line
    if reaction_line == nil then
      local prev_extmark = comment.extmark
      local mark = api.nvim_buf_get_extmark_by_id(bufnr, constants.OCTO_COMMENT_NS, prev_extmark, {details = true})
      local _, end_line = util.get_extmark_region(bufnr, mark)
      insert_line = end_line + 2
    end
    id = comment.id
  elseif kind == "issue" or kind == "pull" then
    -- using the issue body instead
    reaction_groups = api.nvim_buf_get_var(bufnr, "body_reaction_groups")
    reaction_line = api.nvim_buf_get_var(bufnr, "body_reaction_line")
    if reaction_line == nil then
      local prev_extmark = api.nvim_buf_get_var(bufnr, "description").extmark
      local mark = api.nvim_buf_get_extmark_by_id(bufnr, constants.OCTO_COMMENT_NS, prev_extmark, {details = true})
      local _, end_line = util.get_extmark_region(bufnr, mark)
      insert_line = end_line + 2
    end
    id = api.nvim_buf_get_var(bufnr, "iid")
  end

  for _, reaction_group in ipairs(reaction_groups) do
    if reaction_group.content == reaction and reaction_group.viewerHasReacted then
      action = "remove"
      break
    elseif reaction_group.content == reaction and not reaction_group.viewerHasReacted then
      action = "add"
      break
    end
  end
  if action ~= "add" and action ~= "remove"  then
    return
  end


  -- add/delete reaction
  local query = graphql(action.."_reaction_mutation", id, reaction)
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
          elseif action == "remove" then
            reaction_groups = resp.data.removeReaction.subject.reactionGroups
          end

          reaction_line = reaction_line or insert_line + 1
          util.update_reactions_at_cursor(bufnr, reaction_groups, reaction_line)
          if action == "remove" and util.count_reactions(reaction_groups) == 0 then
            -- delete lines
            api.nvim_buf_set_lines(bufnr, reaction_line - 1, reaction_line + 1, false, {})
            api.nvim_buf_clear_namespace(bufnr, constants.OCTO_REACTIONS_VT_NS, reaction_line - 1, reaction_line + 1)
          elseif action == "add" and insert_line then
            -- add lines
            api.nvim_buf_set_lines(bufnr, insert_line, insert_line, false, {"", ""})
          end
          writers.write_reactions(bufnr, reaction_groups, reaction_line)
          util.update_issue_metadata(bufnr)
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
  local repo = util.get_repo_number({"issue", "pull"})
  if not repo then return end

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
  local repo = util.get_repo_number({"issue", "pull"})
  if not repo then return end

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
  local repo = util.get_repo_number({"issue", "pull"})
  if not repo then return end

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
  local repo = util.get_repo_number({"issue", "pull"})
  if not repo then return end
  octo.load_buffer(bufnr)
end

function M.add_label()
  local bufnr = api.nvim_get_current_buf()
  local repo = util.get_repo_number({"issue", "pull"})
  if not repo then return end

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
  local repo = util.get_repo_number({"issue", "pull"})
  if not repo then return end

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
  local repo = util.get_repo_number({"issue", "pull"})
  if not repo then return end

  local iid_ok, iid = pcall(api.nvim_buf_get_var, 0, "iid")
  if not iid_ok or not iid then
    api.nvim_err_writeln("[Octo] Cannot get issue/pr id")
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
  local repo = util.get_repo_number({"issue", "pull"})
  if not repo then return end

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
