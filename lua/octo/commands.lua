local gh = require"octo.gh"
local utils = require"octo.utils"
local navigation = require"octo.navigation"
local window = require"octo.window"
local menu = require"octo.telescope.menu"
local reviews = require"octo.reviews"
local graphql = require"octo.graphql"
local constants = require"octo.constants"
local writers = require"octo.writers"

local M = {}

-- supported commands
M.commands = {
  issue = {
    create = function(repo)
      M.create_issue(repo)
    end,
    edit = function(...)
      utils.get_issue(...)
    end,
    close = function()
      M.change_state("CLOSED")
    end,
    reopen = function()
      M.change_state("OPEN")
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
    end,
    url = function()
      M.copy_url()
    end
  },
  pr = {
    edit = function(...)
      utils.get_pull_request(...)
    end,
    close = function()
      M.change_state("CLOSED")
    end,
    reopen = function()
      M.change_state("OPEN")
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
    end,
    url = function()
      M.copy_url()
    end
  },
  repo = {
    list = function(login)
      menu.repos({login = login})
    end,
    view = function(repo)
      utils.get_repo(nil, repo)
    end,
    fork= function()
      utils.fork_repo()
    end,
    browser = function()
      navigation.open_in_browser()
    end,
    url = function()
      M.copy_url()
    end
  },
  review = {
    start = function()
      reviews.start_review()
    end,
    resume = function()
      reviews.resume_review()
    end,
    comments = function()
      reviews.show_pending_comments()
    end,
    submit = function()
      local current_review = require"octo.reviews".get_current_review()
      if current_review then current_review:collect_submit_info() end
    end,
    discard = function()
      reviews.discard_review()
    end,
    close = function()
      if reviews.get_current_review() and reviews.get_current_review() then
        reviews.get_current_review().layout:close()
      end
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
    remove = function()
      M.remove_label()
    end
  },
  assignee = {
    add = function()
      M.add_user("assignee")
    end,
    remove = function()
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
    remove = function()
      M.remove_project_card()
    end
  }
}

function M.process_varargs(repo, ...)
  local args = table.pack(...)
  if not repo then
    repo = utils.get_remote_name()
  elseif #vim.split(repo, "/") ~= 2 then
    table.insert(args, repo)
    args.n = args.n + 1
    repo = utils.get_remote_name()
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
  if not object then
    print("[Octo] Missing arguments")
    return
  end
  if not vim.g.octo_viewer then
    local name = require"octo".check_login()
    if not name then
      vim.api.nvim_err_writeln("[Octo] You are not logged into any GitHub hosts. Run `gh auth login` to authenticate.")
      return
    end
  end
  local o = M.commands[object]
  if not o then
    local repo, number, kind = utils.parse_url(object)
    if repo and number and kind == "issue" then
      utils.get_issue(repo, number)
    elseif repo and number and kind == "pull" then
      utils.get_pull_request(repo, number)
    else
      print("[Octo] Incorrect argument, valid objects are:" .. vim.inspect(vim.tbl_keys(M.commands)))
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
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer then return end

  local comment_kind, review_id
  if buffer:isReviewThread() then
    comment_kind = "PullRequestReviewComment"
    review_id = reviews.get_current_review().id
  else
    comment_kind = "IssueComment"
  end

  local thread_id, _, thread_end_line, replyTo = utils.get_thread_at_cursor(bufnr)
  if thread_id and not buffer:isReviewThread() then
    vim.api.nvim_err_writeln("[Octo] Start a new review to reply to a thread")
    return
  elseif not thread_id and buffer:isReviewThread() then
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
    pullRequestReview = { id = review_id or -1 },
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
    --vim.fn.execute("normal! Gk")
    --vim.fn.execute("startinsert")
    vim.cmd [[normal Gk]]
    vim.cmd [[startinsert]]
  elseif comment_kind == "PullRequestReviewComment" then
    vim.api.nvim_buf_set_lines(bufnr, thread_end_line, thread_end_line, false, {"x", "x", "x", "x"})
    writers.write_comment(bufnr, comment, comment_kind, thread_end_line + 1)
    vim.fn.execute(":" .. thread_end_line + 3)
    vim.cmd [[startinsert]]
  end

  -- drop undo history
  utils.clear_history()
end

function M.delete_comment()
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer then return end
  local comment, start_line, end_line = utils.get_comment_at_cursor(bufnr)
  if not comment then
    print("[Octo] The cursor does not seem to be located at any comment")
    return
  end
  local query, threadId
  if comment.kind == "IssueComment" then
    query = graphql("delete_issue_comment_mutation", comment.id)
  elseif comment.kind == "PullRequestReviewComment" then
    query = graphql("delete_pull_request_review_comment_mutation", comment.id)
    threadId = utils.get_thread_at_cursor(bufnr)
  elseif comment.kind == "PullRequestReview" then
    -- Review top level comments cannot be deleted here
    return
  end
  local choice = vim.fn.confirm("Delete comment?", "&Yes\n&No\n&Cancel", 2)
  if choice == 1 then
    gh.run(
      {
        args = {"api", "graphql", "-f", string.format("query=%s", query)},
        cb = function(output)
          -- TODO: deleting the last review thread comment, it deletes the whole thread and review
          -- In issue buffers, we should hide the thread snippet
          local resp = vim.fn.json_decode(output)

          if comment.reactionLine then
            vim.api.nvim_buf_set_lines(bufnr, start_line - 2, end_line + 1, false, {})
            vim.api.nvim_buf_clear_namespace(bufnr, constants.OCTO_REACTIONS_VT_NS, start_line - 2, end_line + 1)
          else
            vim.api.nvim_buf_set_lines(bufnr, start_line - 2, end_line - 1, false, {})
          end
          vim.api.nvim_buf_clear_namespace(bufnr, comment.namespace, 0, -1)
          vim.api.nvim_buf_del_extmark(bufnr, constants.OCTO_COMMENT_NS, comment.extmark)
          local comments = buffer.commentsMetadata
          if comments then
            local updated = {}
            for _, c in ipairs(comments) do
              if c.id ~= comment.id then
                table.insert(updated, c)
              end
            end
            buffer.commentsMetadata = updated
          else
            print("ERROR", bufnr)
          end

          if comment.kind == "PullRequestReviewComment" then
            local review = reviews.get_current_review()
            if not review then return end
            local threads = {}
            local pr = resp.data.deletePullRequestReviewComment.pullRequestReview.pullRequest
            threads = pr.reviewThreads.nodes

            local thread_was_deleted = true
            for _, thread in ipairs(threads) do
              if threadId == thread.id then
                thread_was_deleted = false
                break
              end
            end

            local review_was_deleted = true
            for _, thread in ipairs(threads) do
              for _, c in ipairs(thread.comments.nodes) do
                if c.state == "PENDING" then
                  review_was_deleted = false
                  break
                end
              end
            end

            if thread_was_deleted then
              -- this was the last comment on the last thread, close the thread buffer
              local bufname = vim.api.nvim_buf_get_name(bufnr)
              local split = string.match(bufname, "octo://.+/review/[^/]+/threads/([^/]+)/.*")
              if split then
                local diff_win = reviews.get_current_review().layout:cur_file():get_win(split)
                vim.api.nvim_set_current_win(diff_win)
                pcall(vim.api.nvim_buf_delete, bufnr, { force = true})
              end
            end

            if review_was_deleted then
              -- we deleted the last thread of the review and therefore the backend
              -- also deleted the review, create a new one
              review:create(function(resp)
                review.id = resp.data.addPullRequestReview.pullRequestReview.id
                local updated_threads = resp.data.addPullRequestReview.pullRequestReview.pullRequest.reviewThreads.nodes
                review:update_threads(updated_threads)
              end)
            else
              review:update_threads(threads)
            end
          end

        end
      }
    )
  end
end

function M.resolve_thread()
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer then return end
  local thread_id, thread_line = utils.get_thread_at_cursor(bufnr)
  local query = graphql("resolve_review_thread_mutation", thread_id)
  gh.run(
    {
      args = {"api", "graphql", "-f", string.format("query=%s", query)},
      cb = function(output, stderr)
        if stderr and not utils.is_blank(stderr) then
          vim.api.nvim_err_writeln(stderr)
        elseif output then
          local resp = vim.fn.json_decode(output)
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
            local review = reviews.get_current_review()
            if review then review:update_threads(threads) end
            --vim.cmd(string.format("%d,%dfoldclose", thread_line, thread_line))
          end
        end
      end
    }
  )
end

function M.unresolve_thread()
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer then return end
  local thread_id, thread_line = utils.get_thread_at_cursor(bufnr)
  local query = graphql("unresolve_review_thread_mutation", thread_id)
  gh.run(
    {
      args = {"api", "graphql", "-f", string.format("query=%s", query)},
      cb = function(output, stderr)
        if stderr and not utils.is_blank(stderr) then
          vim.api.nvim_err_writeln(stderr)
        elseif output then
          local resp = vim.fn.json_decode(output)
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
            local review = reviews.get_current_review()
            if review then review:update_threads(threads) end
          end
        end
      end
    }
  )
end

function M.change_state(state)
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer then return end

  if not state then
    vim.api.nvim_err_writeln("[Octo] Missing argument: state")
    return
  end

  local id = buffer.node.id
  local query
  if buffer:isIssue() then
    query = graphql("update_issue_state_mutation", id, state)
  elseif buffer:isPullRequest() then
    query = graphql("update_pull_request_state_mutation", id, state)
  end

  gh.run(
    {
      args = {"api", "graphql", "-f", string.format("query=%s", query)},
      cb = function(output, stderr)
        if stderr and not utils.is_blank(stderr) then
          vim.api.nvim_err_writeln(stderr)
        elseif output then
          local resp = vim.fn.json_decode(output)
          local new_state, obj
          if buffer:isIssue() then
            obj = resp.data.updateIssue.issue
            new_state = obj.state
          elseif buffer:isPullRequest() then
            obj = resp.data.updatePullRequest.pullRequest
            new_state = obj.state
          end
          if state == new_state then
            buffer.node.state = new_state
            writers.write_state(bufnr, new_state:upper(), buffer.number)
            writers.write_details(bufnr, obj, true)
            print("[Octo] Issue state changed to: " .. new_state)
          end
        end
      end
    }
  )
end

function M.create_issue(repo)
  if not repo then repo = utils.get_remote_name() end
  if not repo then
    print("[Octo] Cant find repo name")
    return
  end

  vim.fn.inputsave()
  local title = vim.fn.input(string.format("[Octo] Creating issue in %s. Enter title: ", repo))
  vim.fn.inputrestore()

  local repo_id = utils.get_repo_id(repo)
  local query = graphql("create_issue_mutation", repo_id, title, constants.NO_BODY_MSG)
  gh.run(
    {
      args = {"api", "graphql", "-f", string.format("query=%s", query)},
      cb = function(output, stderr)
        if stderr and not utils.is_blank(stderr) then
          vim.api.nvim_err_writeln(stderr)
        elseif output then
          local resp = vim.fn.json_decode(output)
          require"octo".create_buffer("issue", resp.data.createIssue.issue, repo, true)
          vim.fn.execute("normal! Gk")
          vim.fn.execute("startinsert")
        end
      end
    }
  )
end

function M.checkout_pr()
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer or not buffer:isPullRequest() then return end
  if not utils.in_pr_repo() then return end
  gh.run(
    {
      args = {"pr", "checkout", buffer.number, "-R", buffer.repo},
      cb = function(_, stderr)
        if stderr and not utils.is_blank(stderr) then
          for _, line in ipairs(vim.fn.split(stderr, "\n")) do
            if line:match("Switched to branch") or line:match("Already on") then
              print("[Octo]", line)
              return
            end
          end
          vim.api.nvim_err_writeln("[Octo]", stderr)
        end
      end
    }
  )
end

function M.pr_ready_for_review()
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer or not buffer:isPullRequest() then return end
  gh.run(
    {
      args = {"pr", "ready", tostring(buffer.number)},
      cb = function(output, stderr)
        print("[Octo]", output, stderr)
        writers.write_state(bufnr)
      end
    }
  )
end

function M.pr_checks()
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer or not buffer:isPullRequest() then return end
  gh.run(
    {
      args = {"pr", "checks", tostring(buffer.number), "-R", buffer.repo},
      cb = function(output, stderr)
        if stderr and not utils.is_blank(stderr) then
          vim.api.nvim_err_writeln(stderr)
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
          local _, wbufnr = window.create_centered_float({
            header = "Checks",
            content=lines
          })
          local buf_lines = vim.api.nvim_buf_get_lines(wbufnr, 0, -1, false)
          for i, l in ipairs(buf_lines) do
            if #vim.split(l, "pass") > 1 then
              vim.api.nvim_buf_add_highlight(wbufnr, -1, "OctoPassingTest", i - 1, 0, -1)
            elseif #vim.split(l, "fail") > 1 then
              vim.api.nvim_buf_add_highlight(wbufnr, -1, "OctoFailingTest", i - 1, 0, -1)
            end
          end
        end
      end
    }
  )
end

function M.merge_pr(...)
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer or not buffer:isPullRequest() then return end
  local args = {"pr", "merge", tostring(buffer.number)}
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
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer or not buffer:isPullRequest() then return end
  local url = string.format("/repos/%s/pulls/%s", buffer.repo, buffer.number)
  gh.run(
    {
      args = {"api", url},
      headers = {"Accept: application/vnd.github.v3.diff"},
      cb = function(output, stderr)
        if stderr and not utils.is_blank(stderr) then
          vim.api.nvim_err_writeln(stderr)
        elseif output then
          local lines = vim.split(output, "\n")
          local wbufnr = vim.api.nvim_create_buf(true, true)
          vim.api.nvim_buf_set_lines(wbufnr, 0, -1, false, lines)
          vim.api.nvim_set_current_buf(wbufnr)
          vim.api.nvim_buf_set_option(wbufnr, "filetype", "diff")
        end
      end
    }
  )
end

function M.reaction_action(reaction)
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer then return end

  -- normalize reactions
  reaction = reaction:upper()
  if reaction == "+1" then
    reaction = "THUMBS_UP"
  elseif reaction == "-1" then
    reaction = "THUMBS_DOWN"
  elseif reaction == "PARTY" or reaction == "TADA" then
    reaction = "HOORAY"
  end

  local reaction_line, reaction_groups, insert_line, id

  local comment = utils.get_comment_at_cursor(bufnr)
  if comment then
    -- found a comment at cursor
    reaction_groups = comment.reactionGroups
    reaction_line = comment.reactionLine
    if reaction_line == nil then
      local prev_extmark = comment.extmark
      local mark = vim.api.nvim_buf_get_extmark_by_id(bufnr, constants.OCTO_COMMENT_NS, prev_extmark, {details = true})
      local _, end_line = utils.get_extmark_region(bufnr, mark)
      insert_line = end_line + 2
    end
    id = comment.id
  elseif buffer:isIssue() or buffer:isPullRequest() then
    -- using the issue body instead
    reaction_groups = buffer.bodyMetadata.reactionGroups
    reaction_line = buffer.bodyMetadata.reactionLine
    if reaction_line == nil then
      local prev_extmark = buffer.bodyMetadata.extmark
      local mark = vim.api.nvim_buf_get_extmark_by_id(bufnr, constants.OCTO_COMMENT_NS, prev_extmark, {details = true})
      local _, end_line = utils.get_extmark_region(bufnr, mark)
      insert_line = end_line + 2
    end
    id = buffer.node.id
  end

  local action
  for _, reaction_group in ipairs(reaction_groups) do
    if reaction_group.content == reaction and reaction_group.viewerHasReacted then
      action = "remove"
      break
    elseif reaction_group.content == reaction and not reaction_group.viewerHasReacted then
      action = "add"
      break
    end
  end
  if action ~= "add" and action ~= "remove"  then return end

  -- add/delete reaction
  local query = graphql(action.."_reaction_mutation", id, reaction)
  gh.run(
    {
      args = {"api", "graphql", "-f", string.format("query=%s", query)},
      cb = function(output, stderr)
        if stderr and not utils.is_blank(stderr) then
          vim.api.nvim_err_writeln(stderr)
        elseif output then
          local resp = vim.fn.json_decode(output)
          if action == "add" then
            reaction_groups = resp.data.addReaction.subject.reactionGroups
          elseif action == "remove" then
            reaction_groups = resp.data.removeReaction.subject.reactionGroups
          end

          reaction_line = reaction_line or insert_line + 1
          utils.update_reactions_at_cursor(bufnr, reaction_groups, reaction_line)
          if action == "remove" and utils.count_reactions(reaction_groups) == 0 then
            -- delete lines
            vim.api.nvim_buf_set_lines(bufnr, reaction_line - 1, reaction_line + 1, false, {})
            vim.api.nvim_buf_clear_namespace(bufnr, constants.OCTO_REACTIONS_VT_NS, reaction_line - 1, reaction_line + 1)
          elseif action == "add" and insert_line then
            -- add lines
            vim.api.nvim_buf_set_lines(bufnr, insert_line, insert_line, false, {"", ""})
          end
          writers.write_reactions(bufnr, reaction_groups, reaction_line)
          buffer:update_metadata()
        end
      end
    }
  )
end

function M.add_project_card()
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer then return end

  -- show column selection menu
  menu.select_target_project_column(
    function(column_id)
      -- add new card
      local query = graphql("add_project_card_mutation", buffer.node.id, column_id)
      gh.run(
        {
          args = {"api", "graphql", "--paginate", "-f", string.format("query=%s", query)},
          cb = function(output, stderr)
            if stderr and not utils.is_blank(stderr) then
              vim.api.nvim_err_writeln(stderr)
            elseif output then
              -- refresh issue/pr details
              require"octo".load(
                bufnr,
                function(obj)
                  writers.write_details(bufnr, obj, true)
                  buffer.node.projectCards = obj.projectCards
                end
              )
            end
          end
        }
      )
    end
  )
end

function M.remove_project_card()
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer then return end

  -- show card selection menu
  menu.select_project_card(
    function(card)
      -- delete card
      local query = graphql("delete_project_card_mutation", card)
      gh.run(
        {
          args = {"api", "graphql", "--paginate", "-f", string.format("query=%s", query)},
          cb = function(output, stderr)
            if stderr and not utils.is_blank(stderr) then
              vim.api.nvim_err_writeln(stderr)
            elseif output then
              -- refresh issue/pr details
              require"octo".load(
                bufnr,
                function(obj)
                  buffer.node.projectCards = obj.projectCards
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

function M.move_project_card()
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer then return end

  menu.select_project_card(
    function(source_card)
      -- show project column selection menu
      menu.select_target_project_column(
        function(target_column)
          -- move card to selected column
          local query = graphql("move_project_card_mutation", source_card, target_column)
          gh.run(
            {
              args = {"api", "graphql", "--paginate", "-f", string.format("query=%s", query)},
              cb = function(output, stderr)
                if stderr and not utils.is_blank(stderr) then
                  vim.api.nvim_err_writeln(stderr)
                elseif output then
                  -- refresh issue/pr details
                  require"octo".load(
                    bufnr,
                    function(obj)
                      buffer.node.projectCards = obj.projectCards
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
  )
end

function M.reload(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer then return end
  require"octo".load_buffer(bufnr)
end

function M.add_label()
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer then return end

  local iid = buffer.node.id
  if not iid then vim.api.nvim_err_writeln("Cannot get issue/pr id") end

  menu.select_label(
    function(label_id)
      local query = graphql("add_labels_mutation", iid, label_id)
      gh.run(
        {
          args = {"api", "graphql", "--paginate", "-f", string.format("query=%s", query)},
          cb = function(output, stderr)
            if stderr and not utils.is_blank(stderr) then
              vim.api.nvim_err_writeln(stderr)
            elseif output then
              -- refresh issue/pr details
              require"octo".load(
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

function M.remove_label()
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer then return end

  local iid = buffer.node.id
  if not iid then vim.api.nvim_err_writeln("Cannot get issue/pr id") end

  menu.select_assigned_label(
    function(label_id)
      local query = graphql("remove_labels_mutation", iid, label_id)
      gh.run(
        {
          args = {"api", "graphql", "--paginate", "-f", string.format("query=%s", query)},
          cb = function(output, stderr)
            if stderr and not utils.is_blank(stderr) then
              vim.api.nvim_err_writeln(stderr)
            elseif output then
              -- refresh issue/pr details
              require"octo".load(
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
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer then return end

  local iid = buffer.node.id
  if not iid then vim.api.nvim_err_writeln("[Octo] Cannot get issue/pr id") end

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
          args = {"api", "graphql", "--paginate", "-f", string.format("query=%s", query)},
          cb = function(output, stderr)
            if stderr and not utils.is_blank(stderr) then
              vim.api.nvim_err_writeln(stderr)
            elseif output then
              -- refresh issue/pr details
              require"octo".load(
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
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer then return end

  local iid = buffer.node.id
  if not iid then vim.api.nvim_err_writeln("[Octo] Cannot get issue/pr id") end

  menu.select_assignee(
    function(user_id)
      local query = graphql("remove_assignees_mutation", iid, user_id)
      gh.run(
        {
          args = {"api", "graphql", "--paginate", "-f", string.format("query=%s", query)},
          cb = function(output, stderr)
            if stderr and not utils.is_blank(stderr) then
              vim.api.nvim_err_writeln(stderr)
            elseif output then
              -- refresh issue/pr details
              require"octo".load(
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

function M.copy_url()
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer then return end
  local url = buffer.node.url
  vim.fn.setreg('+', url, 'c')
  print("[Octo] Copied URL '".. url .."' to the system clipboard (+ register)")
end

return M
