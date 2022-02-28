local gh = require "octo.gh"
local utils = require "octo.utils"
local navigation = require "octo.navigation"
local window = require "octo.window"
local picker = require "octo.picker"
local reviews = require "octo.reviews"
local graphql = require "octo.graphql"
local constants = require "octo.constants"
local writers = require "octo.writers"

local M = {}

-- supported commands
M.commands = {
  actions = function()
    M.actions()
  end,
  search = function(...)
    M.search(...)
  end,
  issue = {
    create = function(repo)
      M.create_issue(repo)
    end,
    edit = function(...)
      utils.get_issue(...)
    end,
    close = function()
      M.change_state "CLOSED"
    end,
    reopen = function()
      M.change_state "OPEN"
    end,
    list = function(repo, ...)
      local opts = M.process_varargs(repo, ...)
      picker.issues(opts)
    end,
    search = function(repo, ...)
      local opts = M.process_varargs(repo, ...)
      if not opts.repo or opts.repo == vim.NIL then
        opts.repo = utils.get_remote_name()
      end
      if not opts.repo then
        utils.notify("Cannot find repo", 2)
        return
      end
      opts.prompt = "is:issue "
      picker.search(opts)
    end,
    reload = function()
      M.reload()
    end,
    browser = function()
      navigation.open_in_browser()
    end,
    url = function()
      M.copy_url()
    end,
  },
  pr = {
    edit = function(...)
      utils.get_pull_request(...)
    end,
    close = function()
      M.change_state "CLOSED"
    end,
    reopen = function()
      M.change_state "OPEN"
    end,
    list = function(repo, ...)
      local opts = M.process_varargs(repo, ...)
      picker.prs(opts)
    end,
    checkout = function()
      local bufnr = vim.api.nvim_get_current_buf()
      local buffer = octo_buffers[bufnr]
      if not buffer or not buffer:isPullRequest() then
        return
      end
      if not utils.in_pr_repo() then
        return
      end
      utils.checkout_pr(buffer.node.headRefName)
    end,
    create = function(...)
      M.create_pr(...)
    end,
    commits = function()
      picker.commits()
    end,
    changes = function()
      picker.changed_files()
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

      if not opts.repo or opts.repo == vim.NIL then
        opts.repo = utils.get_remote_name()
      end
      if not opts.repo then
        utils.notify("Cannot find repo", 2)
        return
      end
      opts.prompt = "is:pr "
      picker.search(opts)
    end,
    reload = function()
      M.reload()
    end,
    browser = function()
      navigation.open_in_browser()
    end,
    url = function()
      M.copy_url()
    end,
  },
  repo = {
    list = function(login)
      picker.repos { login = login }
    end,
    view = function(repo)
      utils.get_repo(nil, repo)
    end,
    fork = function()
      utils.fork_repo()
    end,
    browser = function()
      navigation.open_in_browser()
    end,
    url = function()
      M.copy_url()
    end,
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
      local current_review = require("octo.reviews").get_current_review()
      if current_review then
        current_review:collect_submit_info()
      end
    end,
    discard = function()
      reviews.discard_review()
    end,
    close = function()
      if reviews.get_current_review() and reviews.get_current_review() then
        reviews.get_current_review().layout:close()
      end
    end,
  },
  gist = {
    list = function(...)
      local args = table.pack(...)
      local opts = {}
      for i = 1, args.n do
        local kv = vim.split(args[i], "=")
        opts[kv[1]] = kv[2]
      end
      picker.gists(opts)
    end,
  },
  thread = {
    resolve = function()
      M.resolve_thread()
    end,
    unresolve = function()
      M.unresolve_thread()
    end,
  },
  comment = {
    add = function()
      M.add_comment()
    end,
    delete = function()
      M.delete_comment()
    end,
  },
  label = {
    create = function(label)
      M.create_label(label)
    end,
    add = function(label)
      M.add_label(label)
    end,
    remove = function(label)
      M.remove_label(label)
    end,
  },
  assignee = {
    add = function(login)
      M.add_user("assignee", login)
    end,
    remove = function(login)
      M.remove_assignee(login)
    end,
  },
  reviewer = {
    add = function(login)
      M.add_user("reviewer", login)
    end,
  },
  reaction = {
    thumbs_up = function()
      M.reaction_action "THUMBS_UP"
    end,
    ["+1"] = function()
      M.reaction_action "THUMBS_UP"
    end,
    thumbs_down = function()
      M.reaction_action "THUMBS_DOWN"
    end,
    ["-1"] = function()
      M.reaction_action "THUMBS_DOWN"
    end,
    eyes = function()
      M.reaction_action "EYES"
    end,
    laugh = function()
      M.reaction_action "LAUGH"
    end,
    confused = function()
      M.reaction_action "CONFUSED"
    end,
    hooray = function()
      M.reaction_action "HOORAY"
    end,
    party = function()
      M.reaction_action "HOORAY"
    end,
    tada = function()
      M.reaction_action "HOORAY"
    end,
    rocket = function()
      M.reaction_action "ROCKET"
    end,
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
    end,
  },
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
    utils.notify("Missing arguments", 1)
    return
  end
  local o = M.commands[object]
  if not o then
    local repo, number, kind = utils.parse_url(object)
    if repo and number and kind == "issue" then
      utils.get_issue(repo, number)
    elseif repo and number and kind == "pull" then
      utils.get_pull_request(repo, number)
    else
      utils.notify("Incorrect argument, valid objects are:" .. vim.inspect(vim.tbl_keys(M.commands)), 1)
      return
    end
  else
    if type(o) == "function" then
      if object == "search" then
        o(action, ...)
      else
        o(...)
      end
      return
    end

    local a = o[action]
    if not a then
      utils.notify("Incorrect action, valid actions are:" .. vim.inspect(vim.tbl_keys(o)), 1)
      return
    else
      a(...)
    end
  end
end

function M.add_comment()
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer then
    return
  end

  local comment_kind, review_id
  if buffer:isReviewThread() then
    comment_kind = "PullRequestReviewComment"
    review_id = reviews.get_current_review().id
  else
    comment_kind = "IssueComment"
  end

  local replyTo, thread_id, thread_end_line
  local _thread = utils.get_thread_at_cursor(bufnr)
  if _thread then
    thread_id = _thread.threadId
    replyTo = _thread.replyTo
    thread_end_line = _thread.bufferEndLine
  end

  if thread_id and not buffer:isReviewThread() then
    utils.notify("Start a new review to reply to a thread", 2)
    return
  elseif not thread_id and buffer:isReviewThread() then
    return
  end

  local comment = {
    id = -1,
    author = { login = vim.g.octo_viewer },
    state = "PENDING",
    createdAt = vim.fn.strftime "%FT%TZ",
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
      { content = "EYES", users = { totalCount = 0 } },
    },
  }

  if comment_kind == "IssueComment" then
    -- just place it at the bottom
    writers.write_comment(bufnr, comment, comment_kind)
    --vim.fn.execute("normal! Gk")
    --vim.fn.execute("startinsert")
    vim.cmd [[normal Gk]]
    vim.cmd [[startinsert]]
  elseif comment_kind == "PullRequestReviewComment" then
    vim.api.nvim_buf_set_lines(bufnr, thread_end_line, thread_end_line, false, { "x", "x", "x", "x" })
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
  if not buffer then
    return
  end
  local comment = utils.get_comment_at_cursor(bufnr)
  local start_line = comment.bufferStartLine
  local end_line = comment.bufferEndLine
  if not comment then
    utils.notify("The cursor does not seem to be located at any comment", 1)
    return
  end
  local query, threadId
  if comment.kind == "IssueComment" then
    query = graphql("delete_issue_comment_mutation", comment.id)
  elseif comment.kind == "PullRequestReviewComment" then
    query = graphql("delete_pull_request_review_comment_mutation", comment.id)
    local _thread = utils.get_thread_at_cursor(bufnr)
    threadId = _thread.threadId
  elseif comment.kind == "PullRequestReview" then
    -- Review top level comments cannot be deleted here
    return
  end
  local choice = vim.fn.confirm("Delete comment?", "&Yes\n&No\n&Cancel", 2)
  if choice == 1 then
    gh.run {
      args = { "api", "graphql", "-f", string.format("query=%s", query) },
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
          utils.notify("ERROR", bufnr, 1)
        end

        if comment.kind == "PullRequestReviewComment" then
          local review = reviews.get_current_review()
          if not review then
            return
          end
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
              pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
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
      end,
    }
  end
end

function M.resolve_thread()
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer then
    return
  end
  local _thread = utils.get_thread_at_cursor(bufnr)
  if not _thread then
    return
  end
  local thread_id = _thread.threadId
  local thread_line = _thread.bufferStartLine
  local query = graphql("resolve_review_thread_mutation", thread_id)
  gh.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.notify(stderr, 2)
      elseif output then
        local resp = vim.fn.json_decode(output)
        local thread = resp.data.resolveReviewThread.thread
        if thread.isResolved then
          -- review thread header
          local start_line = thread.originalStartLine ~= vim.NIL and thread.originalStartLine or thread.originalLine
          local end_line = thread.originalLine
          writers.write_review_thread_header(bufnr, {
            path = thread.path,
            start_line = start_line,
            end_line = end_line,
            isOutdated = thread.isOutdated,
            isResolved = thread.isResolved,
          }, thread_line - 2)
          local threads = resp.data.resolveReviewThread.thread.pullRequest.reviewThreads.nodes
          local review = reviews.get_current_review()
          if review then
            review:update_threads(threads)
          end
          --vim.cmd(string.format("%d,%dfoldclose", thread_line, thread_line))
        end
      end
    end,
  }
end

function M.unresolve_thread()
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer then
    return
  end
  local _thread = utils.get_thread_at_cursor(bufnr)
  if not _thread then
    return
  end
  local thread_id = _thread.threadId
  local thread_line = _thread.bufferStartLine
  local query = graphql("unresolve_review_thread_mutation", thread_id)
  gh.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.notify(stderr, 2)
      elseif output then
        local resp = vim.fn.json_decode(output)
        local thread = resp.data.unresolveReviewThread.thread
        if not thread.isResolved then
          -- review thread header
          local start_line = thread.originalStartLine ~= vim.NIL and thread.originalStartLine or thread.originalLine
          local end_line = thread.originalLine
          writers.write_review_thread_header(bufnr, {
            path = thread.path,
            start_line = start_line,
            end_line = end_line,
            isOutdated = thread.isOutdated,
            isResolved = thread.isResolved,
          }, thread_line - 2)
          local threads = resp.data.unresolveReviewThread.thread.pullRequest.reviewThreads.nodes
          local review = reviews.get_current_review()
          if review then
            review:update_threads(threads)
          end
        end
      end
    end,
  }
end

function M.change_state(state)
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer then
    return
  end

  if not state then
    utils.notify("Missing argument: state", 2)
    return
  end

  local id = buffer.node.id
  local query
  if buffer:isIssue() then
    query = graphql("update_issue_state_mutation", id, state)
  elseif buffer:isPullRequest() then
    query = graphql("update_pull_request_state_mutation", id, state)
  end

  gh.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.notify(stderr, 2)
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
          utils.notify("Issue state changed to: " .. new_state, 1)
        end
      end
    end,
  }
end

function M.create_issue(repo)
  if not repo then
    repo = utils.get_remote_name()
  end
  if not repo then
    utils.notify("Cant find repo name", 1)
    return
  end

  vim.fn.inputsave()
  local title = vim.fn.input(string.format("Creating issue in %s. Enter title: ", repo))
  vim.fn.inputrestore()

  local repo_id = utils.get_repo_id(repo)
  local query = graphql("create_issue_mutation", repo_id, title, constants.NO_BODY_MSG)
  gh.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.notify(stderr, 2)
      elseif output then
        local resp = vim.fn.json_decode(output)
        require("octo").create_buffer("issue", resp.data.createIssue.issue, repo, true)
        vim.fn.execute "normal! Gk"
        vim.fn.execute "startinsert"
      end
    end,
  }
end

function M.create_pr(is_draft)
  is_draft = "draft" == is_draft and true or false
  local repo = utils.get_remote_name()
  if not repo then
    utils.notify("Cant find repo name", 1)
    return
  end

  local owner, name = utils.split_repo(repo)
  local repo_query = graphql("repository_query", owner, name)
  gh.run {
    args = { "api", "graphql", "-f", string.format("query=%s", repo_query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.notify(stderr, 2)
      elseif output then
        local resp = vim.fn.json_decode(output)
        local node = resp.data.repository

        -- repo candidates = self + parent (in case of fork)
        local repo_candidates_entries = { "Seleect target repo", "1. " .. repo }
        local repo_candidates = { repo }
        if node.isFork then
          table.insert(repo_candidates_entries, "2. " .. node.parent.nameWithOwner)
          table.insert(repo_candidates, node.parent.nameWithOwner)
        end

        -- get current local branch
        local cmd = "git rev-parse --abbrev-ref HEAD"
        local local_branch = string.gsub(vim.fn.system(cmd), "%s+", "")

        -- get repo default branch
        local default_branch = node.defaultBranchRef.name

        -- get remote branches
        local remote_branches = node.refs.nodes

        local remote_branch_exists = false
        for _, remote_branch in ipairs(remote_branches) do
          if local_branch == remote_branch.name then
            remote_branch_exists = true
          end
        end
        local remote_branch = local_branch
        if not remote_branch_exists then
          local choice = vim.fn.confirm(
            "Remote branch '" .. local_branch .. "' does not exist. Push local one?",
            "&Yes\n&No\n&Cancel",
            2
          )
          if choice == 1 then
            local remote = "origin"
            remote_branch = vim.fn.input {
              prompt = "Enter remote branch name: ",
              default = local_branch,
              highlight = function(input)
                return { { 0, #input, "String" } }
              end,
            }
            utils.notify(string.format("Pushing '%s' to '%s:%s' ...", local_branch, remote, remote_branch), 1)
            cmd = string.format("git push %s %s:%s", remote, local_branch, remote_branch)
            vim.fn.system(cmd)
          else
            utils.notify("Aborting PR creation", 2)
          end
        end

        vim.fn.inputsave()
        local repo_idx = 1
        if #repo_candidates > 1 then
          repo_idx = vim.fn.inputlist(repo_candidates_entries)
        end
        local last_commit = string.gsub(vim.fn.system "git log -1 --pretty=%B", "%s+$", "")
        local last_commit_lines = vim.split(last_commit, "\n")
        local title = last_commit
        local body = last_commit
        if #last_commit_lines > 1 then
          title = last_commit_lines[1]
          if utils.is_blank(last_commit_lines[2]) and #last_commit_lines > 2 then
            body = table.concat(vim.list_slice(last_commit_lines, 3, #last_commit_lines), "\n")
          else
            body = table.concat(vim.list_slice(last_commit_lines, 2, #last_commit_lines), "\n")
          end
        end
        title = vim.fn.input {
          prompt = "Enter title: ",
          default = title,
          highlight = function(input)
            return { { 0, #input, "String" } }
          end,
        }
        -- The name of the branch you want your changes pulled into. This should be an existing branch on the current repository.
        -- You cannot update the base branch on a pull request to point to another repository.
        local base_ref_name = vim.fn.input {
          prompt = "Enter BASE branch: ",
          default = default_branch,
          highlight = function(input)
            return { { 0, #input, "String" } }
          end,
        }
        -- The name of the branch where your changes are implemented. For cross-repository pull requests in the same network,
        -- namespace head_ref_name with a user like this: username:branch.
        local head_ref_name = vim.fn.input {
          prompt = "Enter HEAD branch: ",
          default = remote_branch,
          highlight = function(input)
            return { { 0, #input, "String" } }
          end,
        }
        if node.isFork and repo_candidates[repo_idx] == node.parent.nameWithOwner then
          head_ref_name = vim.g.octo_viewer .. ":" .. head_ref_name
        end
        vim.fn.inputrestore()

        local repo_id = utils.get_repo_id(repo_candidates[repo_idx])
        local query = graphql("create_pr_mutation", base_ref_name, head_ref_name, repo_id, title, body, is_draft)

        -- print(vim.inspect({
        --   base_ref_name = base_ref_name,
        --   head_ref_name = head_ref_name,
        --   repo_id = repo_id,
        --   title = title,
        --   is_draft = is_draft,
        --   candidates = repo_candidates,
        --   repo = repo_candidates[repo_idx]
        -- }))

        local choice = vim.fn.confirm("Create PR?", "&Yes\n&No\n&Cancel", 2)
        if choice == 1 then
          gh.run {
            args = { "api", "graphql", "-f", string.format("query=%s", query) },
            cb = function(output, stderr)
              if stderr and not utils.is_blank(stderr) then
                utils.notify(stderr, 2)
              elseif output then
                local resp2 = vim.fn.json_decode(output)
                local node2 = resp2.data.createPullRequest.pullRequest
                utils.notify(string.format("#%d - `%s` created successfully", node2.number, node2.title), 1)
                require("octo").create_buffer("pull", node2, repo, true)
                vim.fn.execute "normal! Gk"
                vim.fn.execute "startinsert"
              end
            end,
          }
        end
      end
    end,
  }
end

function M.create_pr(is_draft)
  is_draft = "draft" == is_draft and true or false
  local repo = utils.get_remote_name()
  if not repo then
    utils.notify("Cant find repo name", 1)
    return
  end

  local owner, name = utils.split_repo(repo)
  local repo_query = graphql("repository_query", owner, name)
  gh.run {
    args = { "api", "graphql", "-f", string.format("query=%s", repo_query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.notify(stderr, 2)
      elseif output then
        local resp = vim.fn.json_decode(output)
        local node = resp.data.repository

        -- repo candidates = self + parent (in case of fork)
        local repo_candidates_entries = { "Seleect target repo", "1. " .. repo }
        local repo_candidates = { repo }
        if node.isFork then
          table.insert(repo_candidates_entries, "2. " .. node.parent.nameWithOwner)
          table.insert(repo_candidates, node.parent.nameWithOwner)
        end

        -- get current local branch
        local cmd = "git rev-parse --abbrev-ref HEAD"
        local local_branch = string.gsub(vim.fn.system(cmd), "%s+", "")

        -- get repo default branch
        local default_branch = node.defaultBranchRef.name

        -- get remote branches
        local remote_branches = node.refs.nodes

        local remote_branch_exists = false
        for _, remote_branch in ipairs(remote_branches) do
          if local_branch == remote_branch.name then
            remote_branch_exists = true
          end
        end
        local remote_branch = local_branch
        if not remote_branch_exists then
          local choice = vim.fn.confirm(
            "Remote branch '" .. local_branch .. "' does not exist. Push local one?",
            "&Yes\n&No\n&Cancel",
            2
          )
          if choice == 1 then
            local remote = "origin"
            remote_branch = vim.fn.input {
              prompt = "Enter remote branch name: ",
              default = local_branch,
              highlight = function(input)
                return { { 0, #input, "String" } }
              end,
            }
            utils.notify(string.format("Pushing '%s' to '%s:%s' ...", local_branch, remote, remote_branch), 1)
            cmd = string.format("git push %s %s:%s", remote, local_branch, remote_branch)
            vim.fn.system(cmd)
          else
            utils.notify("Aborting PR creation", 2)
          end
        end

        vim.fn.inputsave()
        local repo_idx = 1
        if #repo_candidates > 1 then
          repo_idx = vim.fn.inputlist(repo_candidates_entries)
        end
        local last_commit = string.gsub(vim.fn.system "git log -1 --pretty=%B", "%s+$", "")
        local last_commit_lines = vim.split(last_commit, "\n")
        local title = last_commit
        local body = last_commit
        if #last_commit_lines > 1 then
          title = last_commit_lines[1]
          if utils.is_blank(last_commit_lines[2]) and #last_commit_lines > 2 then
            body = table.concat(vim.list_slice(last_commit_lines, 3, #last_commit_lines), "\n")
          else
            body = table.concat(vim.list_slice(last_commit_lines, 2, #last_commit_lines), "\n")
          end
        end
        title = vim.fn.input {
          prompt = "Enter title: ",
          default = title,
          highlight = function(input)
            return { { 0, #input, "String" } }
          end,
        }
        -- The name of the branch you want your changes pulled into. This should be an existing branch on the current repository.
        -- You cannot update the base branch on a pull request to point to another repository.
        local base_ref_name = vim.fn.input {
          prompt = "Enter BASE branch: ",
          default = default_branch,
          highlight = function(input)
            return { { 0, #input, "String" } }
          end,
        }
        -- The name of the branch where your changes are implemented. For cross-repository pull requests in the same network,
        -- namespace head_ref_name with a user like this: username:branch.
        local head_ref_name = vim.fn.input {
          prompt = "Enter HEAD branch: ",
          default = remote_branch,
          highlight = function(input)
            return { { 0, #input, "String" } }
          end,
        }
        if node.isFork and repo_candidates[repo_idx] == node.parent.nameWithOwner then
          head_ref_name = vim.g.octo_viewer .. ":" .. head_ref_name
        end
        vim.fn.inputrestore()

        local repo_id = utils.get_repo_id(repo_candidates[repo_idx])
        local query = graphql("create_pr_mutation", base_ref_name, head_ref_name, repo_id, title, body, is_draft)

        -- print(vim.inspect({
        --   base_ref_name = base_ref_name,
        --   head_ref_name = head_ref_name,
        --   repo_id = repo_id,
        --   title = title,
        --   is_draft = is_draft,
        --   candidates = repo_candidates,
        --   repo = repo_candidates[repo_idx]
        -- }))

        local choice = vim.fn.confirm("Create PR?", "&Yes\n&No\n&Cancel", 2)
        if choice == 1 then
          gh.run {
            args = { "api", "graphql", "-f", string.format("query=%s", query) },
            cb = function(output, stderr)
              if stderr and not utils.is_blank(stderr) then
                utils.notify(stderr, 2)
              elseif output then
                local resp2 = vim.fn.json_decode(output)
                local node2 = resp2.data.createPullRequest.pullRequest
                utils.notify(string.format("#%d - `%s` created successfully", node2.number, node2.title), 1)
                require("octo").create_buffer("pull", node2, repo, true)
                vim.fn.execute "normal! Gk"
                vim.fn.execute "startinsert"
              end
            end,
          }
        end
      end
    end,
  }
end

function M.pr_ready_for_review()
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer or not buffer:isPullRequest() then
    return
  end
  gh.run {
    args = { "pr", "ready", tostring(buffer.number) },
    cb = function(output, stderr)
      utils.notify("[Octo]", output, stderr, 1)
      writers.write_state(bufnr)
    end,
  }
end

function M.pr_checks()
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer or not buffer:isPullRequest() then
    return
  end
  gh.run {
    args = { "pr", "checks", tostring(buffer.number), "-R", buffer.repo },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.notify(stderr, 2)
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
        local _, wbufnr = window.create_centered_float {
          header = "Checks",
          content = lines,
        }
        local buf_lines = vim.api.nvim_buf_get_lines(wbufnr, 0, -1, false)
        for i, l in ipairs(buf_lines) do
          if #vim.split(l, "pass") > 1 then
            vim.api.nvim_buf_add_highlight(wbufnr, -1, "OctoPassingTest", i - 1, 0, -1)
          elseif #vim.split(l, "fail") > 1 then
            vim.api.nvim_buf_add_highlight(wbufnr, -1, "OctoFailingTest", i - 1, 0, -1)
          end
        end
      end
    end,
  }
end

function M.merge_pr(...)
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer or not buffer:isPullRequest() then
    return
  end
  local args = { "pr", "merge", tostring(buffer.number) }
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
  gh.run {
    args = args,
    cb = function(output, stderr)
      utils.notify("[Octo]", output, stderr, 1)
      writers.write_state(bufnr)
    end,
  }
end

function M.show_pr_diff()
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer or not buffer:isPullRequest() then
    return
  end
  local url = string.format("/repos/%s/pulls/%s", buffer.repo, buffer.number)
  gh.run {
    args = { "api", url },
    headers = { "Accept: application/vnd.github.v3.diff" },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.notify(stderr, 2)
      elseif output then
        local lines = vim.split(output, "\n")
        local wbufnr = vim.api.nvim_create_buf(true, true)
        vim.api.nvim_buf_set_lines(wbufnr, 0, -1, false, lines)
        vim.api.nvim_set_current_buf(wbufnr)
        vim.api.nvim_buf_set_option(wbufnr, "filetype", "diff")
      end
    end,
  }
end

local function get_reaction_line(bufnr, extmark)
  local prev_extmark = extmark
  local mark = vim.api.nvim_buf_get_extmark_by_id(bufnr, constants.OCTO_COMMENT_NS, prev_extmark, { details = true })
  local _, end_line = utils.get_extmark_region(bufnr, mark)
  return end_line + 3
end

local function get_reaction_info(bufnr, buffer)
  local reaction_groups, reaction_line, insert_line, id
  local comment = utils.get_comment_at_cursor(bufnr)
  if comment then
    -- found a comment at cursor
    id = comment.id
    reaction_groups = comment.reactionGroups
    reaction_line = get_reaction_line(bufnr, comment.extmark)
    if not comment.reactionLine then
      insert_line = true
    end
  elseif buffer:isIssue() or buffer:isPullRequest() then
    -- using the issue body instead
    id = buffer.node.id
    reaction_groups = buffer.bodyMetadata.reactionGroups
    reaction_line = get_reaction_line(bufnr, buffer.bodyMetadata.extmark)
    if not buffer.bodyMetadata.reactionLine then
      insert_line = true
    end
  end
  return reaction_line, reaction_groups, insert_line, id
end

function M.reaction_action(reaction)
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer then
    return
  end

  -- normalize reactions
  reaction = reaction:upper()
  if reaction == "+1" then
    reaction = "THUMBS_UP"
  elseif reaction == "-1" then
    reaction = "THUMBS_DOWN"
  elseif reaction == "PARTY" or reaction == "TADA" then
    reaction = "HOORAY"
  end

  local reaction_line, reaction_groups, insert_line, id = get_reaction_info(bufnr, buffer)

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
  if action ~= "add" and action ~= "remove" then
    return
  end

  -- add/delete reaction
  local query = graphql(action .. "_reaction_mutation", id, reaction)
  gh.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.notify(stderr, 2)
      elseif output then
        local resp = vim.fn.json_decode(output)
        if action == "add" then
          reaction_groups = resp.data.addReaction.subject.reactionGroups
        elseif action == "remove" then
          reaction_groups = resp.data.removeReaction.subject.reactionGroups
        end

        utils.update_reactions_at_cursor(bufnr, reaction_groups, reaction_line)
        if action == "remove" and utils.count_reactions(reaction_groups) == 0 then
          -- delete lines
          vim.api.nvim_buf_set_lines(bufnr, reaction_line - 1, reaction_line + 1, false, {})
          vim.api.nvim_buf_clear_namespace(bufnr, constants.OCTO_REACTIONS_VT_NS, reaction_line - 1, reaction_line + 1)
        elseif action == "add" and insert_line then
          -- add lines
          vim.api.nvim_buf_set_lines(bufnr, reaction_line - 1, reaction_line - 1, false, { "", "" })
        end
        writers.write_reactions(bufnr, reaction_groups, reaction_line)
        buffer:update_metadata()
      end
    end,
  }
end

function M.add_project_card()
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer then
    return
  end

  -- show column selection picker
  picker.project_columns(function(column_id)
    -- add new card
    local query = graphql("add_project_card_mutation", buffer.node.id, column_id)
    gh.run {
      args = { "api", "graphql", "--paginate", "-f", string.format("query=%s", query) },
      cb = function(output, stderr)
        if stderr and not utils.is_blank(stderr) then
          utils.notify(stderr, 2)
        elseif output then
          -- refresh issue/pr details
          require("octo").load(buffer.repo, buffer.kind, buffer.number, function(obj)
            writers.write_details(bufnr, obj, true)
            buffer.node.projectCards = obj.projectCards
          end)
        end
      end,
    }
  end)
end

function M.remove_project_card()
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer then
    return
  end

  -- show card selection picker
  picker.project_cards(function(card)
    -- delete card
    local query = graphql("delete_project_card_mutation", card)
    gh.run {
      args = { "api", "graphql", "--paginate", "-f", string.format("query=%s", query) },
      cb = function(output, stderr)
        if stderr and not utils.is_blank(stderr) then
          utils.notify(stderr, 2)
        elseif output then
          -- refresh issue/pr details
          require("octo").load(buffer.repo, buffer.kind, buffer.number, function(obj)
            buffer.node.projectCards = obj.projectCards
            writers.write_details(bufnr, obj, true)
          end)
        end
      end,
    }
  end)
end

function M.move_project_card()
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer then
    return
  end

  picker.project_cards(function(source_card)
    -- show project column selection picker
    picker.project_columns(function(target_column)
      -- move card to selected column
      local query = graphql("move_project_card_mutation", source_card, target_column)
      gh.run {
        args = { "api", "graphql", "--paginate", "-f", string.format("query=%s", query) },
        cb = function(output, stderr)
          if stderr and not utils.is_blank(stderr) then
            utils.notify(stderr, 2)
          elseif output then
            -- refresh issue/pr details
            require("octo").load(buffer.repo, buffer.kind, buffer.number, function(obj)
              buffer.node.projectCards = obj.projectCards
              writers.write_details(bufnr, obj, true)
            end)
          end
        end,
      }
    end)
  end)
end

function M.reload(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer then
    return
  end
  require("octo").load_buffer(buffer.repo, buffer.kind, buffer.number)
end

function M.create_label(label)
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer then
    return
  end

  local repo_id = utils.get_repo_id(buffer.repo)

  local name, color, description
  if label then
    name = label
    description = ""
    local chars = { "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "B", "C", "D", "E", "F" }
    math.randomseed(os.time())
    color = {}
    for _ = 1, 6 do
      table.insert(color, chars[math.random(1, 16)])
    end
    color = table.concat(color, "")
  else
    vim.fn.inputsave()
    name = vim.fn.input(string.format("Creating label for %s. Enter title: ", buffer.repo))
    color = vim.fn.input "Enter color (RGB): "
    description = vim.fn.input "Enter description: "
    vim.fn.inputrestore()
    color = string.gsub(color, "#", "")
  end

  local query = graphql("create_label_mutation", repo_id, name, description, color)
  gh.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.notify(stderr, 2)
      elseif output then
        local resp = vim.fn.json_decode(output)
        local label = resp.data.createLabel.label
        utils.notify("Created label: " .. label.name, 1)

        -- refresh issue/pr details
        require("octo").load(buffer.repo, buffer.kind, buffer.number, function(obj)
          writers.write_details(bufnr, obj, true)
        end)
      end
    end,
  }
end

function M.add_label(label)
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer then
    return
  end

  local iid = buffer.node.id
  if not iid then
    utils.notify("Cannot get issue/pr id", 2)
  end

  local cb = function(label_id)
    local query = graphql("add_labels_mutation", iid, label_id)
    gh.run {
      args = { "api", "graphql", "-f", string.format("query=%s", query) },
      cb = function(output, stderr)
        if stderr and not utils.is_blank(stderr) then
          utils.notify(stderr, 2)
        elseif output then
          -- refresh issue/pr details
          require("octo").load(buffer.repo, buffer.kind, buffer.number, function(obj)
            writers.write_details(bufnr, obj, true)
          end)
        end
      end,
    }
  end
  if label then
    local label_id = utils.get_label_id(label)
    if label_id then
      cb(label_id)
    else
      utils.notify("Cannot find label: " .. label, 2)
    end
  else
    picker.labels(cb)
  end
end

function M.remove_label(label)
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer then
    return
  end

  local iid = buffer.node.id
  if not iid then
    utils.notify("Cannot get issue/pr id", 2)
  end

  local cb = function(label_id)
    local query = graphql("remove_labels_mutation", iid, label_id)
    gh.run {
      args = { "api", "graphql", "-f", string.format("query=%s", query) },
      cb = function(output, stderr)
        if stderr and not utils.is_blank(stderr) then
          utils.notify(stderr, 2)
        elseif output then
          -- refresh issue/pr details
          require("octo").load(buffer.repo, buffer.kind, buffer.number, function(obj)
            writers.write_details(bufnr, obj, true)
          end)
        end
      end,
    }
  end

  if label then
    local label_id = utils.get_label_id(label)
    if label_id then
      cb(label_id)
    else
      utils.notify("Cannot find label: " .. label, 2)
    end
  else
    picker.assigned_labels(cb)
  end
end

function M.add_user(subject, login)
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer then
    return
  end

  local iid = buffer.node.id
  if not iid then
    utils.notify("Cannot get issue/pr id", 2)
  end

  local cb = function(user_id)
    print(user_id)
    local query
    if subject == "assignee" then
      query = graphql("add_assignees_mutation", iid, user_id)
    elseif subject == "reviewer" then
      query = graphql("request_reviews_mutation", iid, user_id)
    end
    gh.run {
      args = { "api", "graphql", "--paginate", "-f", string.format("query=%s", query) },
      cb = function(output, stderr)
        if stderr and not utils.is_blank(stderr) then
          utils.notify(stderr, 2)
        elseif output then
          -- refresh issue/pr details
          require("octo").load(buffer.repo, buffer.kind, buffer.number, function(obj)
            writers.write_details(bufnr, obj, true)
            vim.cmd [[stopinsert]]
          end)
        end
      end,
    }
  end
  if login then
    local user_id = utils.get_user_id(login)
    if user_id then
      cb(user_id)
    else
      utils.notify("User not found", 2)
    end
  else
    picker.users(cb)
  end
end

function M.remove_assignee(login)
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer then
    return
  end

  local iid = buffer.node.id
  if not iid then
    utils.notify("Cannot get issue/pr id", 2)
  end

  local cb = function(user_id)
    local query = graphql("remove_assignees_mutation", iid, user_id)
    gh.run {
      args = { "api", "graphql", "--paginate", "-f", string.format("query=%s", query) },
      cb = function(output, stderr)
        if stderr and not utils.is_blank(stderr) then
          utils.notify(stderr, 2)
        elseif output then
          -- refresh issue/pr details
          require("octo").load(buffer.repo, buffer.kind, buffer.number, function(obj)
            writers.write_details(bufnr, obj, true)
          end)
        end
      end,
    }
  end
  if login then
    local user_id = utils.get_user_id(login)
    if user_id then
      cb(user_id)
    else
      utils.notify("User not found", 2)
    end
  else
    picker.assignees()
  end
end

function M.copy_url()
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer then
    return
  end
  local url = buffer.node.url
  vim.fn.setreg("+", url, "c")
  utils.notify("Copied URL '" .. url .. "' to the system clipboard (+ register)", 1)
end

function M.actions()
  local flattened_actions = {}

  for object, commands in pairs(M.commands) do
    if object ~= "actions" then
      if type(commands) == "table" then
        for name, fun in pairs(commands) do
          table.insert(flattened_actions, {
            object = object,
            name = name,
            fun = fun,
          })
        end
      end
    end
  end

  picker.actions(flattened_actions)
end

function M.search(...)
  local args = table.pack(...)
  picker.search {
    prompt = table.concat(args, " "),
  }
end

return M
