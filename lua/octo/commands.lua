local constants = require "octo.constants"
local navigation = require "octo.navigation"
local gh = require "octo.gh"
local graphql = require "octo.gh.graphql"
local picker = require "octo.picker"
local reviews = require "octo.reviews"
local window = require "octo.ui.window"
local writers = require "octo.ui.writers"
local utils = require "octo.utils"
local config = require "octo.config"
local colors = require "octo.ui.colors"
local vim = vim

-- a global variable where command handlers can access the details of the last
-- command ran.
--
-- this came into existence since some commands like "comment add" need to
-- understand the line range the comment should be created on.
-- this is problematic without the command options as you exit visual mode when
-- enterting the command line.
OctoLastCmdOpts = nil

local M = {}

local get_current_buffer = function()
  local bufnr = vim.api.nvim_get_current_buf()
  return octo_buffers[bufnr]
end

local function merge_tables(t1, t2)
  local result = vim.deepcopy(t1)
  for k, v in pairs(t2) do
    if type(v) == "table" and type(result[k]) == "table" then
      result[k] = merge_tables(result[k], v)
    else
      result[k] = v
    end
  end
  return result
end

function M.setup()
  vim.api.nvim_create_user_command("Octo", function(opts)
    OctoLastCmdOpts = opts
    require("octo.commands").octo(unpack(opts.fargs))
    OctoLastCmdOpts = nil
  end, { complete = require("octo.completion").octo_command_complete, nargs = "*", range = true })
  local conf = config.values

  local card_commands

  if conf.default_to_projects_v2 then
    card_commands = {
      set = function()
        M.set_project_v2_card()
      end,
      remove = function()
        M.remove_project_v2_card()
      end,
    }
  else
    card_commands = {
      add = function()
        M.add_project_card()
      end,
      move = function()
        M.move_project_card()
      end,
      remove = function()
        M.remove_project_card()
      end,
    }
  end

  -- supported commands
  M.commands = {
    actions = function()
      M.actions()
    end,
    search = function(...)
      M.search(...)
    end,
    discussion = {
      list = function(repo, ...)
        local opts = M.process_varargs(repo, ...)
        picker.discussions(opts)
      end,
    },
    milestone = {
      list = function(repo, ...)
        local opts = M.process_varargs(repo, ...)
        opts.cb = function(item)
          local url = item.url
          utils.info("Opening milestone in browser: " .. url)
          navigation.open_in_browser_raw(url)
        end
        picker.milestones(opts)
      end,
      add = function(milestoneTitle)
        local buffer = get_current_buffer()
        if not buffer then
          utils.error "No buffer found"
          return
        end

        if not utils.is_blank(milestoneTitle) then
          utils.add_milestone(buffer:isIssue(), buffer.number, milestoneTitle)
          return
        end

        local opts = {}
        opts.cb = function(item)
          utils.add_milestone(buffer:isIssue(), buffer.number, item.title)
        end
        picker.milestones(opts)
      end,
      remove = function()
        local buffer = get_current_buffer()
        if not buffer then
          utils.error "No buffer found"
          return
        end

        local milestone = buffer.node.milestone
        if utils.is_blank(milestone) then
          utils.error "No milestone to remove"
          return
        end

        utils.remove_milestone(buffer:isIssue(), buffer.number)
      end,
      create = function(milestoneTitle)
        if utils.is_blank(milestoneTitle) then
          vim.fn.inputsave()
          milestoneTitle = vim.fn.input "Enter milestone title: "
          vim.fn.inputrestore()
        end

        vim.fn.inputsave()
        local description = vim.fn.input "Enter milestone description: "
        vim.fn.inputrestore()

        utils.create_milestone(milestoneTitle, description)
      end,
    },
    issue = {
      create = function(repo)
        M.create_issue(repo)
      end,
      edit = function(...)
        utils.get_issue(...)
      end,
      close = function(stateReason)
        stateReason = stateReason or "CLOSED"
        M.change_state(stateReason)
      end,
      develop = function(repo, ...)
        local bufnr = vim.api.nvim_get_current_buf()
        local buffer = octo_buffers[bufnr]

        if buffer and buffer.kind and buffer.kind == "issue" then
          utils.develop_issue(buffer.repo, buffer.node.number, repo)
        else
          local opts = M.process_varargs(repo, ...)
          opts.cb = function(selected)
            utils.develop_issue(selected.repo, selected.obj.number, repo)
          end
          picker.issues(opts)
        end
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
        if utils.is_blank(opts.repo) then
          utils.error "Cannot find repo"
          return
        end
        local prompt = "is:issue "
        for k, v in pairs(opts) do
          prompt = prompt .. k .. ":" .. v .. " "
        end
        opts.prompt = prompt
        picker.search(opts)
      end,
      reload = function()
        M.reload { verbose = true }
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
          picker.prs {
            cb = function(selected)
              utils.checkout_pr(selected.obj.number)
            end,
          }
          return
        end
        if not utils.in_pr_repo() then
          return
        end
        utils.checkout_pr(buffer.node.number)
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
      draft = function()
        M.pr_draft()
      end,
      search = function(repo, ...)
        local opts = M.process_varargs(repo, ...)
        if utils.is_blank(opts.repo) then
          utils.error "Cannot find repo"
          return
        end
        local prompt = "is:pr "
        for k, v in pairs(opts) do
          prompt = prompt .. k .. ":" .. v .. " "
        end
        opts.prompt = prompt
        opts.search_prs = true
        picker.search(opts)
      end,
      reload = function()
        M.reload { verbose = true }
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
        if repo == nil and utils.cwd_is_git() then
          repo = utils.get_remote_name()
          utils.get_repo(nil, repo)
        elseif repo == nil then
          utils.error "Argument for repo name is required"
        else
          utils.get_repo(nil, repo)
        end
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
        local current_review = reviews.get_current_review()
        if current_review then
          current_review:show_pending_comments()
        else
          utils.error "Please start or resume a review first"
        end
      end,
      submit = function()
        reviews.submit_review()
      end,
      discard = function()
        reviews.discard_review()
      end,
      close = function()
        if reviews.get_current_review() then
          reviews.get_current_review().layout:close()
        else
          utils.error "Please start or resume a review first"
        end
      end,
      commit = function()
        local current_review = reviews.get_current_review()
        if current_review then
          picker.review_commits(function(right, left)
            current_review:focus_commit(right, left)
          end)
        else
          utils.error "Please start or resume a review first"
        end
      end,
      thread = function()
        require("octo.reviews.thread-panel").show_review_threads(true)
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
        local current_review = require("octo.reviews").get_current_review()
        if current_review and utils.in_diff_window() then
          current_review:add_comment(false)
        else
          M.add_pr_issue_or_review_thread_comment()
        end
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
      heart = function()
        M.reaction_action "HEART"
      end,
    },
    card = card_commands,
    cardv2 = {
      set = function(...)
        M.set_project_v2_card()
      end,
      remove = function()
        M.remove_project_v2_card()
      end,
    },
    cardlegacy = {
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
    notification = {
      list = function(repo)
        local opts = {}

        if repo then
          opts.repo = repo
        elseif config.values.notifications.current_repo_only then
          opts.repo = utils.get_remote_name()
        end

        picker.notifications(opts)
      end,
    },
  }

  setmetatable(M.commands.pr, {
    __call = function(_)
      utils.get_pull_request_for_current_branch(function(pr)
        vim.cmd("e " .. utils.get_pull_request_uri(pr.number, pr.repo))
      end)
    end,
  })

  setmetatable(M.commands.review, {
    __call = function(_)
      reviews.start_or_resume_review()
    end,
  })

  setmetatable(M.commands.notification, {
    __call = function(_)
      picker.notifications()
    end,
  })

  local user_defined_commands = config.values.commands
  M.commands = merge_tables(M.commands, user_defined_commands)
end

function M.process_varargs(repo, ...)
  local args = table.pack(...)
  if utils.is_blank(repo) then
    repo = utils.get_remote_name()
  elseif #vim.split(repo, "/") ~= 2 then
    table.insert(args, repo)
    args.n = args.n + 1
    repo = utils.get_remote_name()
  end
  local opts = {}
  for i = 1, args.n do
    local kv = vim.split(args[i], "=")
    if #kv == 2 then
      opts[kv[1]] = kv[2]
    else
      kv = vim.split(args[i], ":")
      if #kv == 2 then
        opts[kv[1]] = kv[2]
      end
    end
  end
  opts.repo = repo
  return opts
end

function M.octo(object, action, ...)
  if not _G.octo_colors_loaded then
    colors.setup()
    _G.octo_colors_loaded = true
  end

  if not object then
    if config.values.enable_builtin then
      M.commands.actions()
    else
      utils.error "Missing arguments"
    end
    return
  end
  local o = M.commands[object]
  if not o then
    local repo, number, kind = utils.parse_url(object)
    if repo and number and kind == "issue" then
      utils.get_issue(number, repo)
    elseif repo and number and kind == "pull" then
      utils.get_pull_request(number, repo)
    else
      utils.error("Incorrect argument: " .. object)
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

    local a = o[action] or o
    if not a then
      utils.error(action and "Incorrect action: " .. action or "No action specified")
      return
    end

    res = pcall(a, ...)
    if not res then
      utils.error(action and "Failed action: " .. action)
      return
    end
  end
end

--- Adds a new comment to an issue/PR or a review thread
function M.add_pr_issue_or_review_thread_comment()
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer then
    return
  end

  local comment_kind
  local comment = {
    id = -1,
    author = { login = vim.g.octo_viewer },
    createdAt = os.date "!%FT%TZ",
    body = " ",
    viewerCanUpdate = true,
    viewerCanDelete = true,
    viewerDidAuthor = true,
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

  local _thread = buffer:get_thread_at_cursor()
  if not utils.is_blank(_thread) and buffer:isReviewThread() then
    comment_kind = "PullRequestReviewComment"
    comment.pullRequestReview = { id = reviews.get_current_review().id }
    comment.state = "PENDING"
    comment.replyTo = _thread.replyTo
    comment.replyToRest = _thread.replyToRest
  elseif not utils.is_blank(_thread) and not buffer:isReviewThread() then
    comment_kind = "PullRequestComment"
    comment.state = ""
    comment.replyTo = _thread.replyTo
    comment.replyToRest = _thread.replyToRest
  elseif utils.is_blank(_thread) and not buffer:isReviewThread() then
    comment_kind = "IssueComment"
  elseif utils.is_blank(_thread) and buffer:isReviewThread() then
    utils.error "Error adding a comment to a review thread"
  end

  if comment_kind == "IssueComment" then
    writers.write_comment(bufnr, comment, comment_kind)
    vim.cmd [[normal Gk]]
    vim.cmd [[startinsert]]
  elseif comment_kind == "PullRequestReviewComment" or comment_kind == "PullRequestComment" then
    vim.api.nvim_buf_set_lines(bufnr, _thread.bufferEndLine, _thread.bufferEndLine, false, { "x", "x", "x", "x" })
    writers.write_comment(bufnr, comment, comment_kind, _thread.bufferEndLine + 1)
    vim.fn.execute(":" .. _thread.bufferEndLine + 3)
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
  local comment = buffer:get_comment_at_cursor()
  if not comment then
    utils.error "The cursor does not seem to be located at any comment"
    return
  end
  local start_line = comment.bufferStartLine
  local end_line = comment.bufferEndLine
  local query, threadId
  if comment.kind == "IssueComment" then
    query = graphql("delete_issue_comment_mutation", comment.id)
  elseif comment.kind == "PullRequestReviewComment" then
    query = graphql("delete_pull_request_review_comment_mutation", comment.id)
    local _thread = buffer:get_thread_at_cursor()
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
        local resp = vim.json.decode(output)

        -- remove comment lines from the buffer
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
        end

        if comment.kind == "PullRequestReviewComment" then
          local review = reviews.get_current_review()
          if not review then
            utils.error "Cannot find review for this comment"
            return
          end

          local threads = resp.data.deletePullRequestReviewComment.pullRequestReview.pullRequest.reviewThreads.nodes

          -- check if there is still at least a PENDING comment
          local review_was_deleted = true
          for _, thread in ipairs(threads) do
            for _, c in ipairs(thread.comments.nodes) do
              if c.state == "PENDING" then
                review_was_deleted = false
                break
              end
            end
          end
          if review_was_deleted then
            -- we deleted the last pending comment and therefore GitHub closed the review, create a new one
            review:create(function(resp)
              review.id = resp.data.addPullRequestReview.pullRequestReview.id
              local updated_threads = resp.data.addPullRequestReview.pullRequestReview.pullRequest.reviewThreads.nodes
              review:update_threads(updated_threads)
            end)
          else
            review:update_threads(threads)
          end

          -- check if we removed the last comment of a thread
          local thread_was_deleted = true
          for _, thread in ipairs(threads) do
            if threadId == thread.id then
              thread_was_deleted = false
              break
            end
          end
          if thread_was_deleted then
            -- this was the last comment, close the thread buffer
            -- No comments left
            utils.error("Deleting buffer " .. tostring(bufnr))
            local bufname = vim.api.nvim_buf_get_name(bufnr)
            local split = string.match(bufname, "octo://.+/review/[^/]+/threads/([^/]+)/.*")
            if split then
              local layout = reviews.get_current_review().layout
              local file = layout:get_current_file()
              if not file then
                return
              end
              local thread_win = file:get_alternative_win(split)
              local original_buf = file:get_alternative_buf(split)
              -- move focus to the split containing the diff buffer
              -- restore the diff buffer so that window is not closed when deleting thread buffer
              vim.api.nvim_win_set_buf(thread_win, original_buf)
              -- delete the thread buffer
              pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
              -- refresh signs and virtual text
              file:place_signs()
              -- diff buffers
              file:show_diff()
            end
          end
        end
      end,
    }
  end
end

local function update_review_thread_header(bufnr, thread, thread_id, thread_line)
  local start_line = thread.originalStartLine ~= vim.NIL and thread.originalStartLine or thread.originalLine
  local end_line = thread.originalLine
  local commit_id = ""
  for _, review_threads in ipairs(thread.pullRequest.reviewThreads.nodes) do
    if review_threads.id == thread_id then
      commit_id = review_threads.comments.nodes[1].originalCommit.abbreviatedOid
    end
  end
  writers.write_review_thread_header(bufnr, {
    path = thread.path,
    start_line = start_line,
    end_line = end_line,
    commit = commit_id,
    isOutdated = thread.isOutdated,
    isResolved = thread.isResolved,
  }, thread_line - 2)
  local threads = thread.pullRequest.reviewThreads.nodes
  local review = reviews.get_current_review()
  if review then
    review:update_threads(threads)
  end
end

function M.resolve_thread()
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer then
    return
  end
  local _thread = buffer:get_thread_at_cursor()
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
        utils.error(stderr)
      elseif output then
        local resp = vim.json.decode(output)
        local thread = resp.data.resolveReviewThread.thread
        if thread.isResolved then
          update_review_thread_header(bufnr, thread, thread_id, thread_line)
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
  local _thread = buffer:get_thread_at_cursor()
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
        utils.error(stderr)
      elseif output then
        local resp = vim.json.decode(output)
        local thread = resp.data.unresolveReviewThread.thread
        if not thread.isResolved then
          update_review_thread_header(bufnr, thread, thread_id, thread_line)
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
    utils.error "Missing argument: state"
    return
  end

  local id = buffer.node.id
  local query, get_obj, desired_state, fields
  if buffer:isIssue() and state == "CLOSED" then
    query = graphql("update_issue_state_mutation", id, state)
    desired_state = state
    get_obj = function(resp)
      return resp.data.updateIssue.issue
    end
    fields = {}
  elseif buffer:isIssue() and state == "OPEN" then
    query = graphql "reopen_issue_mutation"
    desired_state = "OPEN"
    get_obj = function(resp)
      return resp.data.reopenIssue.issue
    end
    fields = { issueId = id }
  elseif buffer:isIssue() then
    query = graphql("close_issue_mutation", id, state)
    desired_state = "CLOSED"
    get_obj = function(resp)
      return resp.data.closeIssue.issue
    end
    fields = {}
  elseif buffer:isPullRequest() then
    query = graphql("update_pull_request_state_mutation", id, state)
    desired_state = state
    get_obj = function(resp)
      return resp.data.updatePullRequest.pullRequest
    end
    fields = {}
  end

  local cb = function(output, stderr)
    if stderr and not utils.is_blank(stderr) then
      utils.error(stderr)
    elseif output then
      local resp = vim.json.decode(output)

      local obj = get_obj(resp)
      local new_state = obj.state

      if desired_state ~= new_state then
        return
      end

      buffer.node.state = new_state

      local updated_state = utils.get_displayed_state(buffer:isIssue(), new_state, obj.stateReason)
      writers.write_state(bufnr, updated_state:upper(), buffer.number)
      writers.write_details(bufnr, obj, true)
      utils.info("Issue state changed to: " .. updated_state)
    end
  end

  gh.graphql {
    query = query,
    fields = fields,
    opts = {
      cb = cb,
    },
  }
end

function M.create_issue(repo)
  if not repo then
    repo = utils.get_remote_name()
  end
  if not repo then
    utils.error "Cant find repo name"
    return
  end

  local templates = utils.get_repo_templates(repo)
  if not utils.is_blank(templates) and #templates.issueTemplates > 0 then
    require("octo.picker").issue_templates(templates.issueTemplates, function(selected)
      M.save_issue {
        repo = repo,
        base_title = selected.title,
        base_body = selected.body,
      }
    end)
  else
    M.save_issue {
      repo = repo,
      base_title = "",
      base_body = "",
    }
  end
end

function M.save_issue(opts)
  vim.fn.inputsave()
  local title = vim.fn.input(string.format("Creating issue in %s. Enter title: ", opts.repo), opts.base_title)
  vim.fn.inputrestore()

  local body
  if utils.is_blank(opts.base_body) then
    local choice = vim.fn.confirm(
      "Do you want to use the content of the current buffer as the body for the new issue?",
      "&Yes\n&No\n&Cancel",
      2
    )
    if choice == 1 then
      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, true)
      body = utils.escape_char(utils.trim(table.concat(lines, "\n")))
    else
      body = constants.NO_BODY_MSG
    end
  else
    body = utils.escape_char(opts.base_body)
    -- TODO: let the user edit the template before submitting
  end

  local repo_id = utils.get_repo_id(opts.repo)
  local query = graphql("create_issue_mutation", repo_id, title, body)
  gh.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
      elseif output then
        local resp = vim.json.decode(output)
        require("octo").create_buffer("issue", resp.data.createIssue.issue, opts.repo, true)
        vim.fn.execute "normal! Gk"
        vim.fn.execute "startinsert"
      end
    end,
  }
end

function M.create_pr(is_draft)
  is_draft = "draft" == is_draft and true or false
  local conf = config.values
  local select = conf.pull_requests.always_select_remote_on_create or false

  local repo
  if select then
    local remotes = utils.get_all_remotes()
    local remote_entries = { "Select base repo," }
    for idx, remote in ipairs(remotes) do
      table.insert(remote_entries, idx .. ". " .. remote.repo)
    end
    local remote_idx = vim.fn.inputlist(remote_entries)
    if remote_idx < 1 then
      utils.error "Aborting PR creation"
      return
    elseif remote_idx > #remotes then
      utils.error "Invaild index."
      return
    end
    repo = remotes[remote_idx].repo
  else
    -- Override the precedence of get_remote, because otherwise upstream is selected
    -- and the check if the local branch creates on the repo fails.
    repo = utils.get_remote_name { "origin" }
    if not repo then
      repo = utils.get_remote_name()
    end
    if not repo then
      utils.error "Cant find repo name"
      return
    end
  end

  -- get repo info
  local info = utils.get_repo_info(repo)

  -- repo candidates = self + parent (in case of fork)
  local repo_candidates_entries = { "Select target repo", "1. " .. repo }
  local repo_candidates = { repo }
  if info.isFork then
    table.insert(repo_candidates_entries, "2. " .. info.parent.nameWithOwner)
    table.insert(repo_candidates, info.parent.nameWithOwner)
  end

  -- get current local branch
  local cmd = "git rev-parse --abbrev-ref HEAD"
  local local_branch = string.gsub(vim.fn.system(cmd), "%s+", "")

  -- get remote branches
  if
    info == nil
    or info.refs == nil
    or info.refs.nodes == nil
    or info == vim.NIL
    or info.refs == vim.NIL
    or info.refs.nodes == vim.NIL
  then
    utils.error "Cannot grab remote branches"
    return
  end
  local remote_branches = info.refs.nodes

  local remote_branch_exists = false
  for _, remote_branch in ipairs(remote_branches) do
    if local_branch == remote_branch.name then
      remote_branch_exists = true
    end
  end
  local remote_branch = local_branch
  if not remote_branch_exists then
    local choice =
      vim.fn.confirm("Remote branch '" .. local_branch .. "' does not exist. Push local one?", "&Yes\n&No\n&Cancel", 2)
    if choice == 1 then
      local remote = "origin"
      remote_branch = vim.fn.input {
        prompt = "Enter remote branch name: ",
        default = local_branch,
        highlight = function(input)
          return { { 0, #input, "String" } }
        end,
      }
      utils.info(string.format("Pushing '%s' to '%s:%s' ...", local_branch, remote, remote_branch))
      local ok, Job = pcall(require, "plenary.job")
      if ok then
        local job = Job:new {
          command = "git",
          args = { "push", remote, local_branch .. ":" .. remote_branch },
          cwd = vim.fn.getcwd(),
        }
        job:sync()
        --local stdout = table.concat(job:result(), "\n")
        local stderr = table.concat(job:stderr_result(), "\n")
        if not utils.is_blank(stderr) then
          utils.error(stderr)
        end
      else
        utils.error "Aborting PR creation"
        return
      end
    else
      utils.error "Aborting PR creation"
      return
    end
  end

  local templates = utils.get_repo_templates(repo)
  local base_body = ""
  if not utils.is_blank(templates) and #templates.pullRequestTemplates > 0 then
    base_body = templates.pullRequestTemplates[1].body
  end
  M.save_pr {
    repo = repo,
    base_title = "",
    base_body = base_body,
    candidates = repo_candidates,
    candidate_entries = repo_candidates_entries,
    is_draft = is_draft,
    info = info,
    remote_branch = remote_branch,
  }
end

function M.save_pr(opts)
  vim.fn.inputsave()
  local repo_idx = 1
  if #opts.candidates > 1 then
    repo_idx = vim.fn.inputlist(opts.candidate_entries)
  end

  -- title and body
  local title, body
  local last_commit = string.gsub(vim.fn.system "git log -1 --pretty=%B", "%s+$", "")
  local last_commit_lines = vim.split(last_commit, "\n")
  if #last_commit_lines >= 1 then
    title = last_commit_lines[1]
  end
  if #last_commit_lines > 1 then
    if utils.is_blank(last_commit_lines[2]) and #last_commit_lines > 2 then
      body = table.concat(vim.list_slice(last_commit_lines, 3, #last_commit_lines), "\n")
    else
      body = table.concat(vim.list_slice(last_commit_lines, 2, #last_commit_lines), "\n")
    end
  end
  if not utils.is_blank(opts.base_body) then
    body = opts.base_body
    --TODO: append last commit?
    -- TODO: let the use edit the body
  end

  -- title
  title = vim.fn.input {
    prompt = "Enter title: ",
    default = title,
    highlight = function(input)
      return { { 0, #input, "String" } }
    end,
  }

  -- The name of the branch you want your changes pulled into. This should be an existing branch on the current repository.
  -- You cannot update the base branch on a pull request to point to another repository.
  -- get repo default branch
  local default_branch = opts.info.defaultBranchRef.name
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
    default = opts.remote_branch,
    highlight = function(input)
      return { { 0, #input, "String" } }
    end,
  }
  if opts.info.isFork and opts.candidates[repo_idx] == opts.info.parent.nameWithOwner then
    head_ref_name = vim.g.octo_viewer .. ":" .. head_ref_name
  end
  vim.fn.inputrestore()

  local repo_id = utils.get_repo_id(opts.candidates[repo_idx])
  title = title and title or ""
  body = body and body or ""
  local query = graphql(
    "create_pr_mutation",
    base_ref_name,
    head_ref_name,
    repo_id,
    utils.escape_char(title),
    utils.escape_char(body),
    opts.is_draft
  )

  local choice = vim.fn.confirm("Create PR?", "&Yes\n&No\n&Cancel", 2)
  if choice == 1 then
    gh.run {
      args = { "api", "graphql", "-f", string.format("query=%s", query) },
      cb = function(output, stderr)
        if stderr and not utils.is_blank(stderr) then
          utils.error(stderr)
        elseif output then
          local resp = vim.json.decode(output)
          local pr = resp.data.createPullRequest.pullRequest
          utils.info(string.format("#%d - `%s` created successfully", pr.number, pr.title))
          require("octo").create_buffer("pull", pr, opts.repo, true)
          vim.fn.execute "normal! Gk"
          vim.fn.execute "startinsert"
        end
      end,
    }
  end
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
      utils.info(output)
      utils.error(stderr)
      writers.write_state(bufnr)
    end,
  }
end

function M.pr_draft()
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer or not buffer:isPullRequest() then
    return
  end
  gh.run {
    args = { "pr", "ready", tostring(buffer.number), "--undo" },
    cb = function(output, stderr)
      utils.info(output)
      utils.error(stderr)
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
        utils.error(stderr)
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
  local conf = config.values

  local merge_method = conf.default_merge_method
  for _, param in ipairs(params) do
    if utils.merge_method_to_flag[param] then
      merge_method = param
    end
  end
  utils.insert_merge_flag(args, merge_method)

  local delete_branch = conf.default_delete_branch
  for _, param in ipairs(params) do
    if param == "delete" then
      delete_branch = true
    end
    if param == "nodelete" then
      delete_branch = false
    end
  end
  utils.insert_delete_flag(args, delete_branch)

  gh.run {
    args = args,
    cb = function(output, stderr)
      utils.info(output .. " " .. stderr)
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
    args = { "api", "--paginate", url },
    headers = { "Accept: application/vnd.github.v3.diff" },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
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
  local comment = buffer:get_comment_at_cursor()
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
        utils.error(stderr)
      elseif output then
        local resp = vim.json.decode(output)
        if action == "add" then
          reaction_groups = resp.data.addReaction.subject.reactionGroups
        elseif action == "remove" then
          reaction_groups = resp.data.removeReaction.subject.reactionGroups
        end

        buffer:update_reactions_at_cursor(reaction_groups, reaction_line)
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
          utils.error(stderr)
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
          utils.error(stderr)
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
            utils.error(stderr)
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

function M.set_project_v2_card()
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer then
    return
  end

  -- show column selection picker
  picker.project_columns_v2(function(project_id, field_id, value)
    -- add new card
    local add_query = graphql("add_project_v2_item_mutation", buffer.node.id, project_id)
    gh.run {
      args = { "api", "graphql", "--paginate", "-f", string.format("query=%s", add_query) },
      cb = function(add_output, add_stderr)
        if add_stderr and not utils.is_blank(add_stderr) then
          utils.error(add_stderr)
        elseif add_output then
          local resp = vim.json.decode(add_output)
          local update_query = graphql(
            "update_project_v2_item_mutation",
            project_id,
            resp.data.addProjectV2ItemById.item.id,
            field_id,
            value
          )
          gh.run {
            args = { "api", "graphql", "--paginate", "-f", string.format("query=%s", update_query) },
            cb = function(update_output, update_stderr)
              if update_stderr and not utils.is_blank(update_stderr) then
                utils.error(update_stderr)
              elseif update_output then
                -- TODO do update here
                -- refresh issue/pr details
                require("octo").load(buffer.repo, buffer.kind, buffer.number, function(obj)
                  writers.write_details(bufnr, obj, true)
                  buffer.node.projectCards = obj.projectCards
                end)
              end
            end,
          }
        end
      end,
    }
  end)
end

function M.remove_project_v2_card()
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer then
    return
  end

  -- show card selection picker
  picker.project_cards_v2(function(project_id, item_id)
    -- delete card
    local query = graphql("delete_project_v2_item_mutation", project_id, item_id)
    gh.run {
      args = { "api", "graphql", "--paginate", "-f", string.format("query=%s", query) },
      cb = function(output, stderr)
        if stderr and not utils.is_blank(stderr) then
          utils.error(stderr)
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

function M.reload(opts)
  require("octo").load_buffer(opts)
end

function M.random_hex_color()
  local chars = { "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "B", "C", "D", "E", "F" }
  math.randomseed(os.time())
  local color = {}
  for _ = 1, 6 do
    table.insert(color, chars[math.random(1, 16)])
  end
  return table.concat(color, "")
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
    color = M.random_hex_color()
    description = ""
  else
    vim.fn.inputsave()
    name = vim.fn.input(string.format("Creating label for %s. Enter title: ", buffer.repo))
    color = vim.fn.input "Enter color (RGB): "
    description = vim.fn.input "Enter description: "
    vim.fn.inputrestore()
    if color == "" then
      color = M.random_hex_color()
    end
    color = string.gsub(color, "#", "")
  end

  local query = graphql("create_label_mutation", repo_id, name, description, color)
  gh.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
      elseif output then
        local resp = vim.json.decode(output)
        local label = resp.data.createLabel.label
        utils.info("Created label: " .. label.name)

        -- refresh issue/pr details
        require("octo").load(buffer.repo, buffer.kind, buffer.number, function(obj)
          writers.write_details(bufnr, obj, true)
        end)
      end
    end,
  }
end

local function format(str)
  return string.format('"%s"', str)
end

local function create_list(values, fmt)
  if type(values) == "string" then
    return fmt(values)
  end

  local formatted_values = {}
  for _, value in ipairs(values) do
    table.insert(formatted_values, fmt(value))
  end
  return "[" .. table.concat(formatted_values, ", ") .. "]"
end

local function label_action(opts)
  local label = opts.label

  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer then
    return
  end

  local iid = buffer.node.id
  if not iid then
    utils.error "Cannot get issue/pr id"
  end

  local cb = function(labels)
    local label_ids = {}
    for _, lbl in ipairs(labels) do
      table.insert(label_ids, lbl.id)
    end

    local query = graphql(opts.query_name, iid, create_list(label_ids, format))
    gh.run {
      args = { "api", "graphql", "-f", string.format("query=%s", query) },
      cb = function(output, stderr)
        if stderr and not utils.is_blank(stderr) then
          utils.error(stderr)
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
      cb { { id = label_id } }
    else
      utils.error("Cannot find label: " .. label)
    end
  else
    opts.labels(cb)
  end
end

function M.add_label(label)
  return label_action {
    query_name = "add_labels_mutation",
    label = label,
    labels = picker.labels,
  }
end

function M.remove_label(label)
  return label_action {
    query_name = "remove_labels_mutation",
    label = label,
    labels = picker.assigned_labels,
  }
end

function M.add_user(subject, login)
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer then
    utils.error "No Octo buffer"
    return
  end

  local iid = buffer.node.id
  if not iid then
    utils.error "Cannot get issue/pr id"
  end

  local cb = function(user_id)
    local query
    if subject == "assignee" then
      query = graphql("add_assignees_mutation", iid, user_id)
    elseif subject == "reviewer" then
      query = graphql("request_reviews_mutation", iid, user_id)
    else
      utils.error "Invalid user type"
      return
    end
    gh.run {
      args = { "api", "graphql", "--paginate", "-f", string.format("query=%s", query) },
      cb = function(output, stderr)
        if stderr and not utils.is_blank(stderr) then
          utils.error(stderr)
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
      utils.error "User not found"
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
    utils.error "Cannot get issue/pr id"
  end

  local cb = function(user_id)
    local query = graphql("remove_assignees_mutation", iid, user_id)
    gh.run {
      args = { "api", "graphql", "--paginate", "-f", string.format("query=%s", query) },
      cb = function(output, stderr)
        if stderr and not utils.is_blank(stderr) then
          utils.error(stderr)
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
      utils.error "User not found"
    end
  else
    picker.assignees(cb)
  end
end

function M.copy_url()
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  local url

  if buffer then
    url = buffer.node.url
  else
    url = utils.get_remote_url()
  end

  vim.fn.setreg("+", url, "c")
  utils.info("Copied URL '" .. url .. "' to the system clipboard (+ register)")
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
