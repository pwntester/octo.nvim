local gh = require "octo.gh"
local signs = require "octo.signs"
local constants = require "octo.constants"
local util = require "octo.util"
local graphql = require "octo.graphql"
local writers = require "octo.writers"
local folds = require "octo.folds"
local window = require "octo.window"
local vim = vim
local api = vim.api
local format = string.format
local json = {
  parse = vim.fn.json_decode,
}

local M = {}

function M.configure_octo_buffer(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()
  local bufname = api.nvim_buf_get_name(bufnr)
  if string.match(bufname, "octo://.+/pull/%d+/file/") then
    -- file diff buffers
    require"octo.reviews".place_thread_signs()
  else
    -- issue/pr/comment buffers
    api.nvim_buf_call(bufnr, function()
      --options
      vim.cmd [[setlocal omnifunc=octo#issue_complete]]
      vim.cmd [[setlocal nonumber norelativenumber nocursorline wrap]]
      vim.cmd [[setlocal foldcolumn=3]]
      vim.cmd [[setlocal signcolumn=yes]]
      vim.cmd [[setlocal conceallevel=2]]
      vim.cmd [[setlocal fillchars=fold:⠀,foldopen:⠀,foldclose:⠀,foldsep:⠀]]
      vim.cmd [[setlocal foldtext=v:lua.OctoFoldText()]]
      vim.cmd [[setlocal foldmethod=manual]]
      vim.cmd [[setlocal foldenable]]
      vim.cmd [[setlocal foldlevelstart=99]]

      -- autocmds
      vim.cmd [[ augroup octo_buffer_autocmds ]]
      vim.cmd(format([[ au! * <buffer=%d> ]], bufnr))
      vim.cmd(format([[ au TextChanged <buffer=%d> lua require"octo.signs".render_signcolumn() ]], bufnr))
      vim.cmd(format([[ au TextChangedI <buffer=%d> lua require"octo.signs".render_signcolumn() ]], bufnr))
      vim.cmd [[ augroup END ]]
    end)
  end
end

function M.load_buffer(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()
  local bufname = vim.fn.bufname(bufnr)
  local repo, type, number = string.match(bufname, "octo://(.+)/(.+)/(%d+)")
  if not repo or not type or not number then
    api.nvim_err_writeln("Incorrect buffer: " .. bufname)
    return
  end

  M.load(bufnr, function(obj)
    M.create_buffer(type, obj, repo, false)
  end)
end

function M.load(bufnr, cb)
  local bufname = vim.fn.bufname(bufnr)
  local repo, type, number = string.match(bufname, "octo://(.+)/(.+)/(%d+)")
  if not repo or not type or not number then
    api.nvim_err_writeln("Incorrect buffer: " .. bufname)
    return
  end
  local owner, name = util.split_repo(repo)
  local query, key
  if type == "pull" then
    query = graphql("pull_request_query", owner, name, number)
    key = "pullRequest"
  elseif type == "issue" then
    query = graphql("issue_query", owner, name, number)
    key = "issue"
  end
  gh.run(
    {
      args = {"api", "graphql", "--paginate", "-f", format("query=%s", query)},
      cb = function(output, stderr)
        if stderr and not util.is_blank(stderr) then
          api.nvim_err_writeln(stderr)
        elseif output then
          local resp = util.aggregate_pages(output, format("data.repository.%s.timelineItems.nodes", key))
          local obj = resp.data.repository[key]
            cb(obj)
        end
      end
    }
  )
end

local function do_save_title_and_body(bufnr, kind)
  local title_metadata = api.nvim_buf_get_var(bufnr, "title")
  local desc_metadata = api.nvim_buf_get_var(bufnr, "description")
  local id = api.nvim_buf_get_var(bufnr, "iid")
  if title_metadata.dirty or desc_metadata.dirty then
    -- trust but verify
    if string.find(title_metadata.body, "\n") then
      api.nvim_err_writeln("Title can't contains new lines")
      return
    elseif title_metadata.body == "" then
      api.nvim_err_writeln("Title can't be blank")
      return
    end

    local query
    if kind == "issue" then
      query = graphql("update_issue_mutation", id, title_metadata.body, desc_metadata.body)
    elseif kind == "pull" then
      query = graphql("update_pull_request_mutation", id, title_metadata.body, desc_metadata.body)
    end
    gh.run(
      {
        args = {"api", "graphql", "-f", format("query=%s", query)},
        cb = function(output, stderr)
          if stderr and not util.is_blank(stderr) then
            api.nvim_err_writeln(stderr)
          elseif output then
            local resp = json.parse(output)
            local obj
            if kind == "pull" then
              obj = resp.data.updatePullRequest.pullRequest
            elseif kind == "issue" then
              obj = resp.data.updateIssue.issue
            end
            if title_metadata.body == obj.title then
              title_metadata.saved_body = obj.title
              title_metadata.dirty = false
              api.nvim_buf_set_var(bufnr, "title", title_metadata)
            end

            if desc_metadata.body == obj.body then
              desc_metadata.saved_body = obj.body
              desc_metadata.dirty = false
              api.nvim_buf_set_var(bufnr, "description", desc_metadata)
            end

            signs.render_signcolumn(bufnr)
            print("[Octo] Saved!")
          end
        end
      }
    )
  end
end

local function do_add_issue_comment(bufnr, metadata)
  -- create new issue comment
  local comments = api.nvim_buf_get_var(bufnr, "comments")
  local id = api.nvim_buf_get_var(bufnr, "iid")
  local add_query = graphql("add_issue_comment_mutation", id, metadata.body)
  gh.run(
    {
      args = {"api", "graphql", "-f", format("query=%s", add_query)},
      cb = function(output, stderr)
        if stderr and not util.is_blank(stderr) then
          api.nvim_err_writeln(stderr)
        elseif output then
          local resp = json.parse(output)
          local resp_body = resp.data.addComment.commentEdge.node.body
          local resp_id = resp.data.addComment.commentEdge.node.id
          if vim.fn.trim(metadata.body) == vim.fn.trim(resp_body) then
            for i, c in ipairs(comments) do
              if tonumber(c.id) == -1 then
                comments[i].id = resp_id
                comments[i].saved_body = resp_body
                comments[i].dirty = false
                break
              end
            end
            api.nvim_buf_set_var(bufnr, "comments", comments)
            signs.render_signcolumn(bufnr)
          end
        end
      end
    }
  )
end

local function do_add_thread_comment(bufnr, metadata)
  -- create new thread reply
  local comments = api.nvim_buf_get_var(bufnr, "comments")
  local query = graphql("add_pull_request_review_comment_mutation", metadata.replyTo, metadata.body, metadata.reviewId)
  gh.run(
    {
      args = {"api", "graphql", "-f", format("query=%s", query)},
      cb = function(output, stderr)
        if stderr and not util.is_blank(stderr) then
          api.nvim_err_writeln(stderr)
        elseif output then
          local resp = json.parse(output)
          local comment = resp.data.addPullRequestReviewComment.comment
          if vim.fn.trim(metadata.body) == vim.fn.trim(comment.body) then
            for i, c in ipairs(comments) do
              if tonumber(c.id) == -1 then
                comments[i].id = comment.id
                comments[i].saved_body = comment.body
                comments[i].dirty = false
                break
              end
            end
            api.nvim_buf_set_var(bufnr, "comments", comments)

            local threads = resp.data.addPullRequestReviewComment.comment.pullRequest.reviewThreads.nodes
            require"octo.reviews".update_threads(threads)
            signs.render_signcolumn(bufnr)
          end
        end
      end
    }
  )
end

local function do_add_new_thread(bufnr, metadata)
  --TODO: How to create a new thread on a line where there is already one
  -- create new thread
  local comments = api.nvim_buf_get_var(bufnr, "comments")
  local query
  if metadata.codeStartLine == metadata.codeEndLine then
    query = graphql("add_pull_request_review_thread_mutation", metadata.reviewId, metadata.body, metadata.path, metadata.diffSide, metadata.codeStartLine)
  else
    query = graphql("add_pull_request_review_multiline_thread_mutation", metadata.reviewId, metadata.body, metadata.path, metadata.diffSide, metadata.diffSide, metadata.codeStartLine, metadata.codeEndLine)
  end
  gh.run(
    {
      args = {"api", "graphql", "-f", format("query=%s", query)},
      cb = function(output, stderr)
        if stderr and not util.is_blank(stderr) then
          api.nvim_err_writeln(stderr)
        elseif output then
          local resp = json.parse(output)
          local comment = resp.data.addPullRequestReviewThread.thread.comments.nodes[1]
          if vim.fn.trim(metadata.body) == vim.fn.trim(comment.body) then
            for i, c in ipairs(comments) do
              if tonumber(c.id) == -1 then
                comments[i].id = comment.id
                comments[i].saved_body = comment.body
                comments[i].dirty = false
                break
              end
            end
            api.nvim_buf_set_var(bufnr, "comments", comments)

            local threads = resp.data.addPullRequestReviewThread.thread.pullRequest.reviewThreads.nodes
            require"octo.reviews".update_threads(threads)
            signs.render_signcolumn(bufnr)

            -- update thread map
            local thread = resp.data.addPullRequestReviewThread.thread
            local review_thread_map = api.nvim_buf_get_var(bufnr, "review_thread_map")
            -- TODO: In a Issue/PR can there be more than one
            local thread_mark_id = vim.tbl_keys(review_thread_map)[1]
            review_thread_map[thread_mark_id] = {
              threadId = thread.id,
              replyTo = thread.comments.nodes[1].id,
              reviewId = thread.comments.nodes[1].pullRequestReview.id
            }
            api.nvim_buf_set_var(bufnr, "review_thread_map", review_thread_map)
          end
        end
      end
    }
  )
end

local function do_update_comment(bufnr, metadata)
  -- update comment/reply
  local comments = api.nvim_buf_get_var(bufnr, "comments")
  local update_query
  if metadata.kind == "IssueComment" then
    update_query = graphql("update_issue_comment_mutation", metadata.id, metadata.body)
  elseif metadata.kind == "PullRequestReviewComment" then
    update_query = graphql("update_pull_request_review_comment_mutation", metadata.id, metadata.body)
  elseif metadata.kind == "PullRequestReview" then
    update_query = graphql("update_pull_request_review_mutation", metadata.id, metadata.body)
  end
  gh.run(
    {
      args = {"api", "graphql", "-f", format("query=%s", update_query)},
      cb = function(output, stderr)
        if stderr and not util.is_blank(stderr) then
          api.nvim_err_writeln(stderr)
        elseif output then
          local resp = json.parse(output)
          local comment
          if metadata.kind == "IssueComment" then
            comment = resp.data.updateIssueComment.issueComment
          elseif metadata.kind == "PullRequestReviewComment" then
            comment = resp.data.updatePullRequestReviewComment.pullRequestReviewComment
            local threads = resp.data.updatePullRequestReviewComment.pullRequestReviewComment.pullRequest.reviewThreads.nodes
            require"octo.reviews".update_threads(threads)
          elseif metadata.kind == "PullRequestReview" then
            comment = resp.data.updatePullRequestReview.pullRequestReview
          end
          if vim.fn.trim(metadata.body) == vim.fn.trim(comment.body) then
            for i, c in ipairs(comments) do
              if c.id == comment.id then
                comments[i].saved_body = comment.body
                comments[i].dirty = false
                break
              end
            end
            api.nvim_buf_set_var(bufnr, "comments", comments)
            signs.render_signcolumn(bufnr)
          end
        end
      end
    }
  )
end

function M.save_buffer()
  local bufnr = api.nvim_get_current_buf()

  local repo = util.get_repo_number({"issue", "pull", "reviewthread"})
  if not repo then
    return
  end

  local kind = util.get_octo_kind(bufnr)

  -- collect comment metadata
  util.update_issue_metadata(bufnr)

  -- title & body
  if kind == "issue" or kind == "pull" then
    do_save_title_and_body(bufnr, kind)
  end

  -- comments
  local comments = api.nvim_buf_get_var(bufnr, "comments")
  for _, metadata in ipairs(comments) do
    if metadata.body ~= metadata.saved_body then
      if metadata.id == -1 then
        if metadata.kind == "IssueComment" then
          do_add_issue_comment(bufnr, metadata)
        elseif metadata.kind == "PullRequestReviewComment" then
          if metadata.replyTo then
            do_add_thread_comment(bufnr, metadata)
          else
            do_add_new_thread(bufnr, metadata)
          end
        end
      else
        do_update_comment(bufnr, metadata)
      end
    end
  end

  -- reset modified option
  api.nvim_buf_set_option(bufnr, "modified", false)
end

function M.on_cursor_hold()
  local _, current_repo = pcall(api.nvim_buf_get_var, 0, "repo")
  if not current_repo then return end

  -- reactions
  local id = util.reactions_at_cursor()
  if id then
    local query = graphql("reactions_for_object_query", id)
    gh.run(
      {
        args = {"api", "graphql", "-f", format("query=%s", query)},
        cb = function(output, stderr)
          if stderr and not util.is_blank(stderr) then
            api.nvim_err_writeln(stderr)
          elseif output then
            local resp = json.parse(output)
            local reactions = {}
            local reactionGroups = resp.data.node.reactionGroups
            for _, reactionGroup in ipairs(reactionGroups) do
              local users = reactionGroup.users.nodes
              local logins = {}
              for _, user in ipairs(users) do
                table.insert(logins, user.login)
              end
              if #logins > 0 then
                reactions[reactionGroup.content] = logins
              end
            end
            local popup_bufnr = api.nvim_create_buf(false, true)
            local lines_count, max_length = writers.write_reactions_summary(popup_bufnr, reactions)
            window.create_popup({
              bufnr = popup_bufnr,
              width = 4 + max_length,
              height = 2 + lines_count
            })
          end
        end
      }
    )
    return
  end

  local login = util.extract_pattern_at_cursor(constants.USER_PATTERN)
  if login then
    local query = graphql("user_profile_query", login)
    gh.run(
      {
        args = {"api", "graphql", "-f", format("query=%s", query)},
        cb = function(output, stderr)
          if stderr and not util.is_blank(stderr) then
            api.nvim_err_writeln(stderr)
          elseif output then
            local resp = json.parse(output)
            local user = resp.data.user
            local popup_bufnr = api.nvim_create_buf(false, true)
            local lines, max_length = writers.write_user_profile(popup_bufnr, user)
            window.create_popup({
              bufnr = popup_bufnr,
              width = 4 + max_length,
              height = 2 + lines
            })
          end
        end
      }
    )
    return
  end

  local repo, number = util.extract_pattern_at_cursor(constants.LONG_ISSUE_PATTERN)

  if not repo or not number then
    repo = current_repo
    number = util.extract_pattern_at_cursor(constants.SHORT_ISSUE_PATTERN)
  end

  if not repo or not number then
    repo, _, number = util.extract_pattern_at_cursor(constants.URL_ISSUE_PATTERN)
  end

  if not repo or not number then return end

  local owner, name = util.split_repo(repo)
  local query = graphql("issue_summary_query", owner, name, number)
  gh.run(
    {
      args = {"api", "graphql", "-f", format("query=%s", query)},
      cb = function(output, stderr)
        if stderr and not util.is_blank(stderr) then
          api.nvim_err_writeln(stderr)
        elseif output then
          local resp = json.parse(output)
          local issue = resp.data.repository.issueOrPullRequest
          local popup_bufnr = api.nvim_create_buf(false, true)
          local max_length = 80
          local lines = writers.write_issue_summary(popup_bufnr, issue, {max_length = max_length})
          window.create_popup({
            bufnr = popup_bufnr,
            width = max_length,
            height = 2 + lines
          })
        end
      end
    }
  )
end

function M.create_buffer(type, obj, repo, create)
  if not obj.id then
    api.nvim_err_writeln(format("Cannot find issue in %s", repo))
    return
  end

  local iid = obj.id
  local number = obj.number
  local state = obj.state

  local bufnr
  if create then
    bufnr = api.nvim_create_buf(true, false)
    api.nvim_set_current_buf(bufnr)
    vim.cmd(format("file octo://%s/%s/%d", repo, type, number))
  else
    bufnr = api.nvim_get_current_buf()
  end

  api.nvim_set_current_buf(bufnr)

  -- clear buffer
  api.nvim_buf_set_lines(bufnr, 0, -1, false, {})

  -- delete extmarks
  for _, m in ipairs(api.nvim_buf_get_extmarks(bufnr, constants.OCTO_COMMENT_NS, 0, -1, {})) do
    api.nvim_buf_del_extmark(bufnr, constants.OCTO_COMMENT_NS, m[1])
  end

  -- configure buffer
  api.nvim_buf_set_option(bufnr, "filetype", "octo")
  api.nvim_buf_set_option(bufnr, "buftype", "acwrite")
  M.configure_octo_buffer(bufnr)

  -- register issue
  api.nvim_buf_set_var(bufnr, "iid", iid)
  api.nvim_buf_set_var(bufnr, "number", number)
  api.nvim_buf_set_var(bufnr, "repo", repo)
  api.nvim_buf_set_var(bufnr, "state", state)
  api.nvim_buf_set_var(bufnr, "labels", obj.labels)
  api.nvim_buf_set_var(bufnr, "assignees", obj.assignees)
  api.nvim_buf_set_var(bufnr, "milestone", obj.milestone)
  api.nvim_buf_set_var(bufnr, "cards", obj.projectCards)
  api.nvim_buf_set_var(bufnr, "taggable_users", {obj.author.login})

  -- buffer mappings
  M.apply_buffer_mappings(bufnr, type)

  -- write title
  writers.write_title(bufnr, obj.title, 1)

  -- write details in buffer
  writers.write_details(bufnr, obj)

  -- write issue/pr status
  writers.write_state(bufnr, state:upper(), number)

  -- write body
  writers.write_body(bufnr, obj)

  -- write body reactions
  local reaction_line
  if util.count_reactions(obj.reactionGroups) > 0 then
    local line = api.nvim_buf_line_count(bufnr) + 1
    writers.write_block(bufnr, {"", ""}, line)
    reaction_line = writers.write_reactions(bufnr, obj.reactionGroups, line)
  end
  api.nvim_buf_set_var(bufnr, "body_reaction_groups", obj.reactionGroups)
  api.nvim_buf_set_var(bufnr, "body_reaction_line", reaction_line)

  -- initialize comments metadata
  api.nvim_buf_set_var(bufnr, "comments", {})

  -- PRs
  if obj.commits then
    -- for pulls, store some additional info
    api.nvim_buf_set_var( bufnr, "pr", {
      id = obj.id,
      isDraft = obj.isDraft,
      merged = obj.merged,
      headRefName = obj.headRefName,
      headRefOid = obj.headRefOid,
      baseRefName = obj.baseRefName,
      baseRefOid = obj.baseRefOid,
      baseRepoName = obj.baseRepository.nameWithOwner
    })
    api.nvim_buf_set_var(bufnr, "review_thread_map", {})
  end

  -- write timeline items
  local prev_is_event = false
  for _, item in ipairs(obj.timelineItems.nodes) do

    if item.__typename == "IssueComment" then
      if prev_is_event then
        writers.write_block(bufnr, {""})
      end

      -- write the comment
      local start_line, end_line = writers.write_comment(bufnr, item, "IssueComment")
      folds.create(bufnr, start_line+1, end_line, true)
      prev_is_event = false

    elseif item.__typename == "PullRequestReview" then
      if prev_is_event then
        writers.write_block(bufnr, {""})
      end

      -- A review can have 0+ threads
      local threads = {}
      for _, comment in ipairs(item.comments.nodes) do
        for _, reviewThread in ipairs(obj.reviewThreads.nodes) do
          if comment.id == reviewThread.comments.nodes[1].id then
            -- found a thread for the current review
            table.insert(threads, reviewThread)
          end
        end
      end

      -- skip reviews with no threads and empty body
      if #threads == 0 and util.is_blank(item.body) then
        goto continue
      end

      -- print review header and top level comment
      local review_start, review_end = writers.write_comment(bufnr, item, "PullRequestReview")

      -- print threads
      if #threads > 0 then
        review_end = writers.write_threads(bufnr, threads, review_start, review_end)
        folds.create(bufnr, review_start+1, review_end, true)
      end
      prev_is_event = false
    elseif item.__typename == "AssignedEvent" then
      writers.write_assigned_event(bufnr, item, prev_is_event)
      prev_is_event = true
    elseif item.__typename == "PullRequestCommit" then
      writers.write_commit_event(bufnr, item, prev_is_event)
      prev_is_event = true
    elseif item.__typename == "MergedEvent" then
      writers.write_merged_event(bufnr, item, prev_is_event)
      prev_is_event = true
    elseif item.__typename == "ClosedEvent" then
      writers.write_closed_event(bufnr, item, prev_is_event)
      prev_is_event = true
    elseif item.__typename == "ReopenedEvent" then
      writers.write_reopened_event(bufnr, item, prev_is_event)
      prev_is_event = true
    elseif item.__typename == "LabeledEvent" then
      writers.write_labeled_event(bufnr, item, "added")
      prev_is_event = true
    elseif item.__typename == "UnlabeledEvent" then
      writers.write_labeled_event(bufnr, item, "removed")
      prev_is_event = true
    end
    ::continue::
  end
  if prev_is_event then
    writers.write_block(bufnr, {""})
  end

  M.async_fetch_taggable_users(bufnr, repo, obj.participants.nodes)
  M.async_fetch_issues(bufnr, repo)

  -- show signs
  signs.render_signcolumn(bufnr)

  -- drop undo history
  vim.fn["octo#clear_history"]()

  -- reset modified option
  api.nvim_buf_set_option(bufnr, "modified", false)
end

function M.check_editable()
  local bufnr = api.nvim_get_current_buf()

  local body = util.get_body_at_cursor(bufnr)
  if body and body.viewerCanUpdate then
    return
  end

  local comment = util.get_comment_at_cursor(bufnr)
  if comment and comment.viewerCanUpdate then
    return
  end

  local key = api.nvim_replace_termcodes("<esc>", true, false, true)
  api.nvim_feedkeys(key, "m", true)
  print("[Octo] Cannot make changes to non-editable regions")
end

function M.apply_buffer_mappings(bufnr, kind)
  local mapping_opts = {silent = true, noremap = true}

  if kind == "issue" then
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      "<space>ic",
      [[<cmd>lua require'octo.commands'.change_issue_state('closed')<CR>]],
      mapping_opts
    )
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      "<space>io",
      [[<cmd>lua require'octo.commands'.change_issue_state('open')<CR>]],
      mapping_opts
    )

    local repo_ok, repo = pcall(api.nvim_buf_get_var, bufnr, "repo")
    if repo_ok then
      api.nvim_buf_set_keymap(
        bufnr,
        "n",
        "<space>il",
        format("<cmd>lua require'octo.menu'.issues('%s')<CR>", repo),
        mapping_opts
      )
    end
  elseif kind == "pull" then
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      "<space>po",
      [[<cmd>lua require'octo.commands'.checkout_pr()<CR>]],
      mapping_opts
    )
    api.nvim_buf_set_keymap(bufnr, "n", "<space>pc", [[<cmd>lua require'octo.menu'.commits()<CR>]], mapping_opts)
    api.nvim_buf_set_keymap(bufnr, "n", "<space>pf", [[<cmd>lua require'octo.menu'.files()<CR>]], mapping_opts)
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      "<space>pd",
      [[<cmd>lua require'octo.commands'.show_pr_diff()<CR>]],
      mapping_opts
    )
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      "<space>pm",
      [[<cmd>lua require'octo.commands'.merge_pr("commit")<CR>]],
      mapping_opts
    )
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      "<space>va",
      [[<cmd>lua require'octo.commands'.add_user('reviewer')<CR>]],
      mapping_opts
    )
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      "<space>vd",
      [[<cmd>lua require'octo.commands'.remove_user('reviewer')<CR>]],
      mapping_opts
    )
  end

  if kind == "issue" or kind == "pull" then
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      "<c-r>",
      [[<cmd>lua require'octo.commands'.reload()<CR>]],
      mapping_opts
    )
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      "<c-o>",
      [[<cmd>lua require'octo.navigation'.open_in_browser()<CR>]],
      mapping_opts
    )
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      "<space>la",
      [[<cmd>lua require'octo.commands'.add_label()<CR>]],
      mapping_opts
    )
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      "<space>ld",
      [[<cmd>lua require'octo.commands'.delete_label()<CR>]],
      mapping_opts
    )

    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      "<space>aa",
      [[<cmd>lua require'octo.commands'.add_user('assignee')<CR>]],
      mapping_opts
    )
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      "<space>ad",
      [[<cmd>lua require'octo.commands'.remove_user('assignee')<CR>]],
      mapping_opts
    )
  end

  if kind == "issue" or kind == "pull" or kind == "reviewthread" then
    -- autocomplete
    api.nvim_buf_set_keymap(bufnr, "i", "@", "@<C-x><C-o>", mapping_opts)
    api.nvim_buf_set_keymap(bufnr, "i", "#", "#<C-x><C-o>", mapping_opts)

    -- navigation
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      "<space>gi",
      [[<cmd>lua require'octo.navigation'.go_to_issue()<CR>]],
      mapping_opts
    )
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      "]c",
      [[<cmd>lua require'octo'.next_comment()<CR>]],
      mapping_opts
    )
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      "[c",
      [[<cmd>lua require'octo'.prev_comment()<CR>]],
      mapping_opts
    )

    -- comments
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      "<space>ca",
      [[<cmd>lua require'octo.commands'.add_comment()<CR>]],
      mapping_opts
    )

    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      "<space>cd",
      [[<cmd>lua require'octo.commands'.delete_comment()<CR>]],
      mapping_opts
    )

    -- reactions
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      "<space>rp",
      [[<cmd>lua require'octo.commands'.reaction_action('hooray')<CR>]],
      mapping_opts
    )
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      "<space>rh",
      [[<cmd>lua require'octo.commands'.reaction_action('heart')<CR>]],
      mapping_opts
    )
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      "<space>re",
      [[<cmd>lua require'octo.commands'.reaction_action('eyes')<CR>]],
      mapping_opts
    )
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      "<space>r+",
      [[<cmd>lua require'octo.commands'.reaction_action('+1')<CR>]],
      mapping_opts
    )
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      "<space>r-",
      [[<cmd>lua require'octo.commands'.reaction_action('-1')<CR>]],
      mapping_opts
    )
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      "<space>rr",
      [[<cmd>lua require'octo.commands'.reaction_action('rocket')<CR>]],
      mapping_opts
    )
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      "<space>rl",
      [[<cmd>lua require'octo.commands'.reaction_action('laugh')<CR>]],
      mapping_opts
    )
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      "<space>rc",
      [[<cmd>lua require'octo.commands'.reaction_action('confused')<CR>]],
      mapping_opts
    )
  end
end

function M.next_comment()
  local bufnr = api.nvim_get_current_buf()
  local kind = util.get_octo_kind(bufnr)
  if kind then
    local cursor = api.nvim_win_get_cursor(0)
    local current_line = cursor[1]
    local lines = util.get_sorted_comment_lines()
    lines = util.tbl_slice(lines, 3, #lines)
    local target
    if current_line < lines[1]+1 then
      -- go to first comment
      target = lines[1]+1
    elseif current_line > lines[#lines]+1 then
      -- do not move
      target = current_line - 1
    else
      for i=#lines, 1, -1 do
        if current_line >= lines[i]+1 then
          target = lines[i+1]+1
          break
        end
      end
    end
    api.nvim_win_set_cursor(0, {target+1, cursor[2]})
  end
end

function M.prev_comment()
  local bufnr = api.nvim_get_current_buf()
  local kind = util.get_octo_kind(bufnr)
  if kind then
    local cursor = api.nvim_win_get_cursor(0)
    local current_line = cursor[1]
    local lines = util.get_sorted_comment_lines()
    lines = util.tbl_slice(lines, 3, #lines)
    local target
    if current_line > lines[#lines]+2 then
      -- go to last comment
      target = lines[#lines]+1
    elseif current_line <= lines[1]+2 then
      -- do not move
      target = current_line - 1
    else
      for i=1, #lines, 1 do
        if current_line <= lines[i]+2 then
          target = lines[i-1]+1
          break
        end
      end
    end
    api.nvim_win_set_cursor(0, {target+1, cursor[2]})
  end
end

-- This function accumulates all the taggable users into a single list that
-- gets set as a buffer variable `taggable_users`. If this list of users
-- is needed syncronously, this function will need to be refactored.
-- The list of taggable users should contain:
--   - The PR author
--   - The authors of all the existing comments
--   - The contributors of the repo
function M.async_fetch_taggable_users(bufnr, repo, participants)
  local users = api.nvim_buf_get_var(bufnr, "taggable_users") or {}

  -- add participants
  for _, p in pairs(participants) do
    table.insert(users, p.login)
  end

  -- add comment authors
  local comments_metadata = api.nvim_buf_get_var(bufnr, "comments")
  for _, c in pairs(comments_metadata) do
    table.insert(users, c.author)
  end

  -- add repo contributors
  api.nvim_buf_set_var(bufnr, "taggable_users", users)
  gh.run(
    {
      args = {"api", format("repos/%s/contributors", repo)},
      cb = function(response)
        local resp = json.parse(response)
        for _, contributor in ipairs(resp) do
          table.insert(users, contributor.login)
        end
        api.nvim_buf_set_var(bufnr, "taggable_users", users)
      end
    }
  )
end

-- This function fetches the issues in the repo so they can be used for
-- completion.
function M.async_fetch_issues(bufnr, repo)
  gh.run(
    {
      args = {"api", format(format("repos/%s/issues", repo))},
      cb = function(response)
        local issues_metadata = {}
        local resp = json.parse(response)
        for _, issue in ipairs(resp) do
          table.insert(issues_metadata, {number = issue.number, title = issue.title})
        end
        api.nvim_buf_set_var(bufnr, "issues", issues_metadata)
      end
    }
  )
end

function M.check_login()
  gh.run(
    {
      args = {"auth", "status"},
      cb = function(_, err)
        local _, _, name = string.find(err, "Logged in to [^%s]+ as ([^%s]+)")
        vim.g.octo_viewer = name
      end
    }
  )
end

return M
