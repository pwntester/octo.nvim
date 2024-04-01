local utils = require "octo.utils"
local cli = require "octo.backend.gh.cli"
local graphql = require "octo.backend.gh.graphql"
local constants = require "octo.constants"
local window = require "octo.ui.window"
local writers = require "octo.ui.writers"

local _, Job = pcall(require, "plenary.job")

local M = {}

---@param repo string
---@param kind string
---@param number integer
---@param cb function
function M.load(repo, kind, number, cb)
  local owner, name = utils.split_repo(repo)
  local query, key

  if kind == "pull" then
    query = graphql("pull_request_query", owner, name, number, _G.octo_pv2_fragment)
    key = "pullRequest"
  elseif kind == "issue" then
    query = graphql("issue_query", owner, name, number, _G.octo_pv2_fragment)
    key = "issue"
  elseif kind == "repo" then
    query = graphql("repository_query", owner, name)
    key = "repo"
  end

  cli.run {
    args = { "api", "graphql", "--paginate", "--jq", ".", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        vim.api.nvim_err_writeln(stderr)
      elseif output then
        if kind == "pull" or kind == "issue" then
          local resp = utils.aggregate_pages(output, string.format("data.repository.%s.timelineItems.nodes", key))
          local obj = resp.data.repository[key]
          cb(obj)
        elseif kind == "repo" then
          local resp = vim.fn.json_decode(output)
          local obj = resp.data.repository
          cb(obj)
        end
      end
    end,
  }
end

---@param id string
function M.reactions_popup(id)
  local query = graphql("reactions_for_object_query", id)

  cli.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        vim.api.nvim_err_writeln(stderr)
      elseif output then
        local resp = vim.fn.json_decode(output)
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
        local popup_bufnr = vim.api.nvim_create_buf(false, true)
        local lines_count, max_length = writers.write_reactions_summary(popup_bufnr, reactions)
        window.create_popup {
          bufnr = popup_bufnr,
          width = 4 + max_length,
          height = 2 + lines_count,
        }
      end
    end,
  }
end

---@param login string
function M.user_popup(login)
  local query = graphql("user_profile_query", login)

  cli.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        vim.api.nvim_err_writeln(stderr)
      elseif output then
        local resp = vim.fn.json_decode(output)
        local user = resp.data.user
        local popup_bufnr = vim.api.nvim_create_buf(false, true)
        local lines, max_length = writers.write_user_profile(popup_bufnr, user)
        window.create_popup {
          bufnr = popup_bufnr,
          width = 4 + max_length,
          height = 2 + lines,
        }
      end
    end,
  }
end

---@param repo string
---@param number integer IID
function M.link_popup(repo, number)
  local owner, name = utils.split_repo(repo)
  local query = graphql("issue_summary_query", owner, name, number)

  cli.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        vim.api.nvim_err_writeln(stderr)
      elseif output then
        local resp = vim.fn.json_decode(output)
        local issue = resp.data.repository.issueOrPullRequest
        local popup_bufnr = vim.api.nvim_create_buf(false, true)
        local max_length = 80
        local lines = writers.write_issue_summary(popup_bufnr, issue, { max_length = max_length })
        window.create_popup {
          bufnr = popup_bufnr,
          width = max_length,
          height = 2 + lines,
        }
      end
    end,
  }
end

---@param comment CommentMetadata
---@param buffer OctoBuffer
---@param bufnr integer
function M.cmds_delete_comment(comment, buffer, bufnr)
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
    cli.run {
      args = { "api", "graphql", "-f", string.format("query=%s", query) },
      cb = function(output)
        -- TODO: deleting the last review thread comment, it deletes the whole thread and review
        -- In issue buffers, we should hide the thread snippet
        local resp = vim.fn.json_decode(output)

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
          local review = require("octo.reviews").get_current_review()
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
              local layout = require("octo.reviews").get_current_review().layout
              local file = layout:cur_file()
              local diff_win = file:get_win(split)
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

---@param bufnr integer
---@param thread table Graphql Reponse Thread
---@param thread_id string
---@param thread_line integer
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
    resolvedBy = { login = vim.g.octo_viewer },
  }, thread_line - 2)
  local threads = thread.pullRequest.reviewThreads.nodes
  local review = require("octo.reviews").get_current_review()
  if review then
    review:update_threads(threads)
  end
end

---@param thread ThreadMetadata
---@param bufnr integer
function M.cmds_resolve_thread(thread, bufnr)
  local thread_id = thread.threadId
  local thread_line = thread.bufferStartLine

  local query = graphql("resolve_review_thread_mutation", thread_id)
  cli.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
      elseif output then
        local resp = vim.fn.json_decode(output)
        local resp_thread = resp.data.resolveReviewThread.thread
        if resp_thread.isResolved then
          update_review_thread_header(bufnr, resp_thread, thread_id, thread_line)
          --vim.cmd(string.format("%d,%dfoldclose", thread_line, thread_line))
        end
      end
    end,
  }
end

---@param thread ThreadMetadata
---@param bufnr integer
function M.cmds_unresolve_thread(thread, bufnr)
  local thread_id = thread.threadId
  local thread_line = thread.bufferStartLine

  local query = graphql("unresolve_review_thread_mutation", thread_id)
  cli.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
      elseif output then
        local resp = vim.fn.json_decode(output)
        local resp_thread = resp.data.unresolveReviewThread.thread
        if not resp_thread.isResolved then
          update_review_thread_header(bufnr, resp_thread, thread_id, thread_line)
        end
      end
    end,
  }
end

---@param buffer OctoBuffer
---@param bufnr integer
---@param state string CLOSED or OPEN
function M.cmds_change_state(buffer, bufnr, state)
  local id = buffer.node.id
  local query
  if buffer:isIssue() then
    query = graphql("update_issue_state_mutation", id, state)
  elseif buffer:isPullRequest() then
    query = graphql("update_pull_request_state_mutation", id, state)
  end

  cli.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
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
          utils.info("Issue state changed to: " .. new_state)
        end
      end
    end,
  }
end

---@param repo string
---@param title string
---@param body string
function M.cmds_save_issue(repo, title, body)
  local repo_id = utils.get_repo_id(repo)
  local query = graphql("create_issue_mutation", repo_id, title, body)

  cli.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
      elseif output then
        local resp = vim.fn.json_decode(output)
        require("octo").create_buffer("issue", resp.data.createIssue.issue, repo, true)
        vim.fn.execute "normal! Gk"
        vim.fn.execute "startinsert"
      end
    end,
  }
end

---@param candidates table
---@param repo string
---@param repo_idx integer
---@param title string
---@param body string
---@param base_ref_name string
---@param head_ref_name string
---@param is_draft boolean
function M.cmds_save_pr(candidates, repo, repo_idx, title, body, base_ref_name, head_ref_name, is_draft)
  local repo_id = utils.get_repo_id(candidates[repo_idx])
  title = title and title or ""
  body = body and body or ""
  local query = graphql(
    "create_pr_mutation",
    base_ref_name,
    head_ref_name,
    repo_id,
    utils.escape_char(title),
    utils.escape_char(body),
    is_draft
  )

  local choice = vim.fn.confirm("Create PR?", "&Yes\n&No\n&Cancel", 2)
  if choice == 1 then
    cli.run {
      args = { "api", "graphql", "-f", string.format("query=%s", query) },
      cb = function(output, stderr)
        if stderr and not utils.is_blank(stderr) then
          utils.error(stderr)
        elseif output then
          local resp = vim.fn.json_decode(output)
          local pr = resp.data.createPullRequest.pullRequest
          utils.info(string.format("#%d - `%s` created successfully", pr.number, pr.title))
          require("octo").create_buffer("pull", pr, repo, true)
          vim.fn.execute "normal! Gk"
          vim.fn.execute "startinsert"
        end
      end,
    }
  end
end

---@param bufnr integer
---@param number integer MR IID
function M.cmds_mark_pr_ready(bufnr, number)
  cli.run {
    args = { "pr", "ready", tostring(number) },
    cb = function(output, stderr)
      utils.info(output)
      utils.error(stderr)
      writers.write_state(bufnr)
    end,
  }
end

---@param bufnr integer
---@param number integer MR IID
function M.cmds_mark_pr_draft(bufnr, number)
  cli.run {
    args = { "pr", "ready", tostring(number), "--undo" },
    cb = function(output, stderr)
      utils.info(output)
      utils.error(stderr)
      writers.write_state(bufnr)
    end,
  }
end

---@param buffer OctoBuffer
function M.cmds_pr_checks(buffer)
  cli.run {
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

---@param params table
---@param buffer OctoBuffer
---@param bufnr integer MR IID
---@param default_merge_method string
function M.cmds_merge_pr(params, buffer, bufnr, default_merge_method)
  local args = { "pr", "merge", tostring(buffer.number) }
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
    if default_merge_method == "squash" then
      table.insert(args, "--squash")
    elseif default_merge_method == "rebase" then
      table.insert(args, "--rebase")
    else
      table.insert(args, "--merge")
    end
  end
  cli.run {
    args = args,
    cb = function(output, stderr)
      utils.info(output .. " " .. stderr)
      writers.write_state(bufnr)
    end,
  }
end

---@param buffer OctoBuffer
function M.cmds_show_pr_diff(buffer)
  local url = string.format("/repos/%s/pulls/%s", buffer.repo, buffer.number)
  cli.run {
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

---add/delete reaction
---@param reaction string THUMBS_UP or THUMBS_DOWN or HOORAY
---@param id string
---@param buffer OctoBuffer
---@param bufnr integer
---@param action string add or remove
---@param reaction_line integer
---@param insert_line boolean
function M.cmds_reaction_action(reaction, id, buffer, bufnr, action, reaction_line, insert_line)
  local query = graphql(action .. "_reaction_mutation", id, reaction)
  cli.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
      elseif output then
        local resp = vim.fn.json_decode(output)
        local reaction_groups
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

---@param buffer OctoBuffer
---@param bufnr integer
---@param column_id string
function M.cmds_add_project_card(buffer, bufnr, column_id)
  local query = graphql("add_project_card_mutation", buffer.node.id, column_id)
  cli.run {
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
end

---@param buffer OctoBuffer
---@param bufnr integer
---@param card string
function M.cmds_remove_project_card(buffer, bufnr, card)
  local query = graphql("delete_project_card_mutation", card)
  cli.run {
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
end

---@param buffer OctoBuffer
---@param bufnr integer
---@param source_card string
---@param target_column string
function M.cmds_move_project_card(buffer, bufnr, source_card, target_column)
  local query = graphql("move_project_card_mutation", source_card, target_column)
  cli.run {
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
end

---@param buffer OctoBuffer
---@param bufnr integer
---@param project_id string
---@param field_id string
---@param value string
function M.cmds_set_project_card_v2(buffer, bufnr, project_id, field_id, value)
  local add_query = graphql("add_project_v2_item_mutation", buffer.node.id, project_id)
  cli.run {
    args = { "api", "graphql", "--paginate", "-f", string.format("query=%s", add_query) },
    cb = function(add_output, add_stderr)
      if add_stderr and not utils.is_blank(add_stderr) then
        utils.error(add_stderr)
      elseif add_output then
        local resp = vim.fn.json_decode(add_output)
        local update_query = graphql(
          "update_project_v2_item_mutation",
          project_id,
          resp.data.addProjectV2ItemById.item.id,
          field_id,
          value
        )
        cli.run {
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
end

---@param buffer OctoBuffer
---@param bufnr integer
---@param project_id string
---@param item_id string
function M.cmds_remove_project_card_v2(buffer, bufnr, project_id, item_id)
  local query = graphql("delete_project_v2_item_mutation", project_id, item_id)
  cli.run {
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
end

---@param buffer OctoBuffer
---@param bufnr integer
---@param name string
---@param description string
---@param color string
function M.cmds_create_label(buffer, bufnr, name, description, color)
  local repo_id = utils.get_repo_id(buffer.repo)
  local query = graphql("create_label_mutation", repo_id, name, description, color)
  cli.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
      elseif output then
        local resp = vim.fn.json_decode(output)
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

---@param buffer OctoBuffer
---@param bufnr integer
---@param iid string
---@param label_id string
function M.cmds_add_label(buffer, bufnr, iid, label_id)
  local query = graphql("add_labels_mutation", iid, label_id)
  cli.run {
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

---@param buffer OctoBuffer
---@param bufnr integer
---@param iid string
---@param label_id string
function M.cmds_remove_label(buffer, bufnr, iid, label_id)
  local query = graphql("remove_labels_mutation", iid, label_id)
  cli.run {
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

---assignee or reviewer dynamicly depending on subject
---@param buffer OctoBuffer
---@param bufnr integer
---@param iid string
---@param user_id string
---@param subject string
function M.cmds_add_user(buffer, bufnr, iid, user_id, subject)
  local query
  if subject == "assignee" then
    query = graphql("add_assignees_mutation", iid, user_id)
  elseif subject == "reviewer" then
    query = graphql("request_reviews_mutation", iid, user_id)
  else
    utils.error "Invalid user type"
    return
  end
  cli.run {
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

---@param buffer OctoBuffer
---@param bufnr integer
---@param iid string
---@param user_id string
function M.cmds_remove_assignee(buffer, bufnr, iid, user_id)
  local query = graphql("remove_assignees_mutation", iid, user_id)
  cli.run {
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

---Add repo contributors
---@param repo string
---@param users table
function M.buffer_fetch_taggable_users(repo, users)
  cli.run {
    args = { "api", string.format("repos/%s/contributors", repo) },
    cb = function(response)
      if not utils.is_blank(response) then
        local resp = vim.fn.json_decode(response)
        for _, contributor in ipairs(resp) do
          table.insert(users, contributor.login)
        end
      end
    end,
  }
end

---Fetches the issues in the repo so they can be used for completion.
---@param repo string
function M.buffer_fetch_issues(repo)
  cli.run {
    args = { "api", string.format("repos/%s/issues", repo) },
    cb = function(response)
      local issues_metadata = {}
      local resp = vim.fn.json_decode(response)
      for _, issue in ipairs(resp) do
        table.insert(issues_metadata, { number = issue.number, title = issue.title })
      end
      octo_repo_issues[repo] = issues_metadata
    end,
  }
end

---@param buffer OctoBuffer
---@param id string
---@param title_metadata TitleMetadata
---@param desc_metadata BodyMetadata
function M.buffer_save_title_and_body(buffer, id, title_metadata, desc_metadata)
  local query
  if buffer:isIssue() then
    query = graphql("update_issue_mutation", id, title_metadata.body, desc_metadata.body)
  elseif buffer:isPullRequest() then
    query = graphql("update_pull_request_mutation", id, title_metadata.body, desc_metadata.body)
  end

  cli.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        vim.api.nvim_err_writeln(stderr)
      elseif output then
        local resp = vim.fn.json_decode(output)
        local obj
        if buffer:isPullRequest() then
          obj = resp.data.updatePullRequest.pullRequest
        elseif buffer:isIssue() then
          obj = resp.data.updateIssue.issue
        end
        if title_metadata.body == obj.title then
          title_metadata.savedBody = obj.title
          title_metadata.dirty = false
          buffer.titleMetadata = title_metadata
        end

        if desc_metadata.body == obj.body then
          desc_metadata.savedBody = obj.body
          desc_metadata.dirty = false
          buffer.bodyMetadata = desc_metadata
        end

        buffer:render_signs()
        utils.info "Saved!"
      end
    end,
  }
end

---@param buffer OctoBuffer
---@param id string
---@param comment_metadata CommentMetadata
function M.buffer_add_issue_comment(buffer, id, comment_metadata)
  local query = graphql("add_issue_comment_mutation", id, comment_metadata.body)
  cli.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        vim.api.nvim_err_writeln(stderr)
      elseif output then
        local resp = vim.fn.json_decode(output)
        local respBody = resp.data.addComment.commentEdge.node.body
        local respId = resp.data.addComment.commentEdge.node.id
        if utils.trim(comment_metadata.body) == utils.trim(respBody) then
          local comments = buffer.commentsMetadata
          for i, c in ipairs(comments) do
            if tonumber(c.id) == -1 then
              comments[i].id = respId
              comments[i].savedBody = respBody
              comments[i].dirty = false
              break
            end
          end
          buffer:render_signs()
        end
      end
    end,
  }
end

---Create new thread reply
---@param buffer OctoBuffer
---@param comment_metadata CommentMetadata
function M.buffer_add_thread_comment(buffer, comment_metadata)
  local query = graphql(
    "add_pull_request_review_comment_mutation",
    comment_metadata.replyTo,
    comment_metadata.body,
    comment_metadata.reviewId
  )

  cli.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        vim.api.nvim_err_writeln(stderr)
      elseif output then
        local resp = vim.fn.json_decode(output)
        local resp_comment = resp.data.addPullRequestReviewComment.comment
        local comment_end
        if utils.trim(comment_metadata.body) == utils.trim(resp_comment.body) then
          local comments = buffer.commentsMetadata
          for i, c in ipairs(comments) do
            if tonumber(c.id) == -1 then
              comments[i].id = resp_comment.id
              comments[i].savedBody = resp_comment.body
              comments[i].dirty = false
              comment_end = comments[i].endLine
              break
            end
          end

          local threads = resp_comment.pullRequest.reviewThreads.nodes
          local review = require("octo.reviews").get_current_review()
          if review then
            review:update_threads(threads)
          end

          buffer:render_signs()

          -- update thread map
          local thread_id
          for _, thread in ipairs(threads) do
            for _, c in ipairs(thread.comments.nodes) do
              if c.id == resp_comment.id then
                thread_id = thread.id
                break
              end
            end
          end
          local mark_id
          for markId, threadMetadata in pairs(buffer.threadsMetadata) do
            if threadMetadata.threadId == thread_id then
              mark_id = markId
            end
          end
          local extmark = vim.api.nvim_buf_get_extmark_by_id(
            buffer.bufnr,
            constants.OCTO_THREAD_NS,
            tonumber(mark_id),
            { details = true }
          )
          local thread_start = extmark[1]
          -- update extmark
          vim.api.nvim_buf_del_extmark(buffer.bufnr, constants.OCTO_THREAD_NS, tonumber(mark_id))
          local thread_mark_id = vim.api.nvim_buf_set_extmark(buffer.bufnr, constants.OCTO_THREAD_NS, thread_start, 0, {
            end_line = comment_end + 2,
            end_col = 0,
          })
          buffer.threadsMetadata[tostring(thread_mark_id)] = buffer.threadsMetadata[tostring(mark_id)]
          buffer.threadsMetadata[tostring(mark_id)] = nil
        end
      end
    end,
  }
end

---Basic Thread/Comment without code?
---@param buffer OctoBuffer
---@param comment_metadata CommentMetadata
---@param review Review
---@param isMultiline boolean
function M.buffer_pr_add_thread(buffer, comment_metadata, review, isMultiline)
  local query
  if isMultiline then
    query = graphql(
      "add_pull_request_review_multiline_thread_mutation",
      comment_metadata.reviewId,
      comment_metadata.body,
      comment_metadata.path,
      comment_metadata.diffSide,
      comment_metadata.diffSide,
      comment_metadata.snippetStartLine,
      comment_metadata.snippetEndLine
    )
  else
    query = graphql(
      "add_pull_request_review_thread_mutation",
      comment_metadata.reviewId,
      comment_metadata.body,
      comment_metadata.path,
      comment_metadata.diffSide,
      comment_metadata.snippetStartLine
    )
  end
  cli.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        vim.api.nvim_err_writeln(stderr)
      elseif output then
        local resp = vim.fn.json_decode(output).data.addPullRequestReviewThread
        if not utils.is_blank(resp.thread) then
          local new_comment = resp.thread.comments.nodes[1]
          if utils.trim(comment_metadata.body) == utils.trim(new_comment.body) then
            local comments = buffer.commentsMetadata
            for i, c in ipairs(comments) do
              if tonumber(c.id) == -1 then
                comments[i].id = new_comment.id
                comments[i].savedBody = new_comment.body
                comments[i].dirty = false
                break
              end
            end
            local threads = resp.thread.pullRequest.reviewThreads.nodes
            if review then
              review:update_threads(threads)
            end
            buffer:render_signs()
          end
        else
          utils.error "Failed to create thread"
          return
        end
      end
    end,
  }
end

---@param buffer OctoBuffer
---@param comment_metadata CommentMetadata
---@param review Review
---@param position integer
function M.buffer_commit_add_thread(buffer, comment_metadata, review, position)
  local query = graphql(
    "add_pull_request_review_commit_thread_mutation",
    review.layout.right.commit,
    comment_metadata.body,
    comment_metadata.reviewId,
    comment_metadata.path,
    position
  )
  cli.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        vim.api.nvim_err_writeln(stderr)
      elseif output then
        local r = vim.fn.json_decode(output)
        local resp = r.data.addPullRequestReviewComment
        if not utils.is_blank(resp.comment) then
          if utils.trim(comment_metadata.body) == utils.trim(resp.comment.body) then
            local comments = buffer.commentsMetadata
            for i, c in ipairs(comments) do
              if tonumber(c.id) == -1 then
                comments[i].id = resp.comment.id
                comments[i].savedBody = resp.comment.body
                comments[i].dirty = false
                break
              end
            end
            if review then
              local threads = resp.comment.pullRequest.reviewThreads.nodes
              review:update_threads(threads)
            end
            buffer:render_signs()
          end
        else
          utils.error "Failed to create thread"
          return
        end
      end
    end,
  }
end

---@param buffer OctoBuffer
---@param comment_metadata CommentMetadata
function M.buffer_add_pr_comment(buffer, comment_metadata)
  cli.run {
    args = {
      "api",
      "--method",
      "POST",
      string.format("/repos/%s/pulls/%d/comments/%s/replies", buffer.repo, buffer.number, comment_metadata.replyToRest),
      "-f",
      string.format([[body=%s]], utils.escape_char(comment_metadata.body)),
      "--jq",
      ".",
    },
    headers = { "Accept: application/vnd.github.v3+json" },
    cb = function(output, stderr)
      if not utils.is_blank(stderr) then
        utils.error(stderr)
      elseif output then
        local resp = vim.fn.json_decode(output)
        if not utils.is_blank(resp) then
          if utils.trim(comment_metadata.body) == utils.trim(resp.body) then
            local comments = buffer.commentsMetadata
            for i, c in ipairs(comments) do
              if tonumber(c.id) == -1 then
                comments[i].id = resp.id
                comments[i].savedBody = resp.body
                comments[i].dirty = false
                break
              end
            end
            buffer:render_signs()
          end
        else
          utils.error "Failed to create thread"
          return
        end
      end
    end,
  }
end

---@param buffer OctoBuffer
---@param comment_metadata CommentMetadata
function M.buffer_update_comment(buffer, comment_metadata)
  local update_query
  if comment_metadata.kind == "IssueComment" then
    update_query = graphql("update_issue_comment_mutation", comment_metadata.id, comment_metadata.body)
  elseif comment_metadata.kind == "PullRequestReviewComment" then
    update_query = graphql("update_pull_request_review_comment_mutation", comment_metadata.id, comment_metadata.body)
  elseif comment_metadata.kind == "PullRequestReview" then
    update_query = graphql("update_pull_request_review_mutation", comment_metadata.id, comment_metadata.body)
  end
  cli.run {
    args = { "api", "graphql", "-f", string.format("query=%s", update_query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        vim.api.nvim_err_writeln(stderr)
      elseif output then
        local resp = vim.fn.json_decode(output)
        local resp_comment
        if comment_metadata.kind == "IssueComment" then
          resp_comment = resp.data.updateIssueComment.issueComment
        elseif comment_metadata.kind == "PullRequestReviewComment" then
          resp_comment = resp.data.updatePullRequestReviewComment.pullRequestReviewComment
          local threads =
            resp.data.updatePullRequestReviewComment.pullRequestReviewComment.pullRequest.reviewThreads.nodes
          local review = require("octo.reviews").get_current_review()
          if review then
            review:update_threads(threads)
          end
        elseif comment_metadata.kind == "PullRequestReview" then
          resp_comment = resp.data.updatePullRequestReview.pullRequestReview
        end
        if resp_comment and utils.trim(comment_metadata.body) == utils.trim(resp_comment.body) then
          local comments = buffer.commentsMetadata
          for i, c in ipairs(comments) do
            if c.id == comment_metadata.id then
              comments[i].savedBody = comment_metadata.body
              comments[i].dirty = false
              break
            end
          end
          buffer:render_signs()
        end
      end
    end,
  }
end

---@param repo string
---@param number integer IID
function M.pr_get_diff(repo, number)
  local url = string.format("repos/%s/pulls/%d", repo, number)
  return cli.run {
    args = { "api", "--paginate", url },
    headers = { "Accept: application/vnd.github.v3.diff" },
    mode = "sync",
  }
end

---@param pr PullRequest
---@param cb function
function M.pr_get_changed_files(pr, cb)
  local url = string.format("repos/%s/pulls/%d/files", pr.repo, pr.number)
  cli.run {
    args = { "api", "--paginate", url, "--jq", "." },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
      elseif output then
        local FileEntry = require("octo.reviews.file-entry").FileEntry
        local results = vim.fn.json_decode(output)
        local files = {}
        for _, result in ipairs(results) do
          local entry = FileEntry:new {
            path = result.filename,
            previous_path = result.previous_filename,
            patch = result.patch,
            pull_request = pr,
            status = utils.file_status_map[result.status],
            stats = {
              additions = result.additions,
              deletions = result.deletions,
              changes = result.changes,
            },
          }
          table.insert(files, entry)
        end
        cb(files)
      end
    end,
  }
end

---Ongoing review: Octo review commit
---@param pr PullRequest
---@param rev Rev
---@param cb function
function M.pr_get_commit_changed_files(pr, rev, cb)
  local url = string.format("repos/%s/commits/%s", pr.repo, rev.commit)
  cli.run {
    args = { "api", "--paginate", url, "--jq", "." },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
      elseif output then
        local FileEntry = require("octo.reviews.file-entry").FileEntry
        local results = vim.fn.json_decode(output)
        local files = {}
        if results.files then
          for _, result in ipairs(results.files) do
            local entry = FileEntry:new {
              path = result.filename,
              previous_path = result.previous_filename,
              patch = result.patch,
              pull_request = pr,
              status = utils.file_status_map[result.status],
              stats = {
                additions = result.additions,
                deletions = result.deletions,
                changes = result.changes,
              },
            }
            table.insert(files, entry)
          end
          cb(files)
        end
      end
    end,
  }
end

---@param repo string
---@param kind string
---@param number integer
---@param remote string
function M.open_in_browser(repo, kind, number, remote)
  local cmd
  if not kind and not repo then
    local bufnr = vim.api.nvim_get_current_buf()
    local buffer = octo_buffers[bufnr]
    if not buffer then
      return
    end
    if buffer:isPullRequest() then
      cmd = string.format("gh pr view --web -R %s/%s %d", remote, buffer.repo, buffer.number)
    elseif buffer:isIssue() then
      cmd = string.format("gh issue view --web -R %s/%s %d", remote, buffer.repo, buffer.number)
    elseif buffer:isRepo() then
      cmd = string.format("gh repo view --web %s/%s", remote, buffer.repo)
    end
  else
    if kind == "pr" or kind == "pull_request" then
      cmd = string.format("gh pr view --web -R %s/%s %d", remote, repo, number)
    elseif kind == "issue" then
      cmd = string.format("gh issue view --web -R %s/%s %d", remote, repo, number)
    elseif kind == "repo" then
      cmd = string.format("gh repo view --web %s", remote, repo.url)
    elseif kind == "gist" then
      cmd = string.format("gh gist view --web %s", number)
    elseif kind == "project" then
      cmd = string.format("gh project view --owner %s --web %s", repo, number)
    end
  end
  pcall(vim.cmd, "silent !" .. cmd)
end

---@param repo string
---@param number integer
function M.go_to_issue(repo, number)
  local owner, name = utils.split_repo(repo)
  local query = graphql("issue_kind_query", owner, name, number)
  cli.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        vim.api.nvim_err_writeln(stderr)
      elseif output then
        local resp = vim.fn.json_decode(output)
        local kind = resp.data.repository.issueOrPullRequest.__typename
        if kind == "Issue" then
          utils.get_issue(repo, number)
        elseif kind == "PullRequest" then
          utils.get_pull_request(repo, number)
        end
      end
    end,
  }
end

---@param file FileEntry
function M.file_toggle_viewed(file)
  local query, next_state
  if file.viewed_state == "VIEWED" then
    query = graphql("unmark_file_as_viewed_mutation", file.path, file.pull_request.id)
    next_state = "UNVIEWED"
  elseif file.viewed_state == "UNVIEWED" then
    query = graphql("mark_file_as_viewed_mutation", file.path, file.pull_request.id)
    next_state = "VIEWED"
  elseif file.viewed_state == "DISMISSED" then
    query = graphql("mark_file_as_viewed_mutation", file.path, file.pull_request.id)
    next_state = "VIEWED"
  end
  cli.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        vim.api.nvim_err_writeln(stderr)
      elseif output then
        --local resp = vim.fn.json_decode(output)
        file.viewed_state = next_state
        local current_review = require("octo.reviews").get_current_review()
        if current_review then
          current_review.layout.file_panel:render()
          current_review.layout.file_panel:redraw()
        end
      end
    end,
  }
end

---@param pr_id string
function M.review_start_review_mutation(pr_id, cb)
  local query = graphql("start_review_mutation", pr_id)
  cli.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
      elseif output then
        local resp = vim.fn.json_decode(output)
        cb(resp)
      end
    end,
  }
end

---@param pull_request PullRequest
function M.review_retrieve(pull_request, cb)
  local query = graphql("pending_review_threads_query", pull_request.owner, pull_request.name, pull_request.number)
  cli.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
      elseif output then
        local resp = vim.fn.json_decode(output)
        cb(resp)
      end
    end,
  }
end

---@param review Review
function M.review_discard(review)
  local query = graphql(
    "pending_review_threads_query",
    review.pull_request.owner,
    review.pull_request.name,
    review.pull_request.number
  )
  cli.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        vim.error(stderr)
      elseif output then
        local resp = vim.fn.json_decode(output)
        if #resp.data.repository.pullRequest.reviews.nodes == 0 then
          utils.error "No pending reviews found"
          return
        end
        review.id = resp.data.repository.pullRequest.reviews.nodes[1].id

        local choice = vim.fn.confirm("All pending comments will get deleted, are you sure?", "&Yes\n&No\n&Cancel", 2)
        if choice == 1 then
          local delete_query = graphql("delete_pull_request_review_mutation", review.id)
          cli.run {
            args = { "api", "graphql", "-f", string.format("query=%s", delete_query) },
            cb = function(output, stderr)
              if stderr and not utils.is_blank(stderr) then
                vim.error(stderr)
              elseif output then
                review.id = -1
                review.threads = {}
                review.files = {}
                utils.info "Pending review discarded"
                vim.cmd [[tabclose]]
              end
            end,
          }
        end
      end
    end,
  }
end

---@param id integer
---@param layout Layout
---@param event string
function M.review_submit(id, layout, event)
  local bufnr = vim.api.nvim_get_current_buf()
  local winid = vim.api.nvim_get_current_win()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local body = utils.escape_char(utils.trim(table.concat(lines, "\n")))
  local query = graphql("submit_pull_request_review_mutation", id, event, body, { escape = false })
  cli.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
      elseif output then
        utils.info "Review was submitted successfully!"
        pcall(vim.api.nvim_win_close, winid, 0)
        layout:close()
      end
    end,
  }
end

---@param pr_number integer
function M.util_checkout_pr(pr_number)
  Job:new({
    enable_recording = true,
    command = "gh",
    args = { "pr", "checkout", pr_number },
    on_exit = vim.schedule_wrap(function()
      local output = vim.fn.system "git branch --show-current"
      utils.info("Switched to " .. output)
    end),
  }):start()
end

---@param pr_number integer
function M.util_checkout_pr_sync(pr_number)
  Job:new({
    enable_recording = true,
    command = "gh",
    args = { "pr", "checkout", pr_number },
    on_exit = vim.schedule_wrap(function()
      local output = vim.fn.system "git branch --show-current"
      utils.info("Switched to " .. output)
    end),
  }):sync()
end

---@param pr_number integer
function M.util_merge_pr(pr_number)
  Job:new({
    enable_recording = true,
    command = "gh",
    args = { "pr", "merge", pr_number, "--merge", "--delete-branch" },
    on_exit = vim.schedule_wrap(function()
      utils.info("Merged PR " .. pr_number .. "!")
    end),
  }):start()
end

---@param repo string
function M.util_get_repo_iid(repo)
  local owner, name = utils.split_repo(repo)
  local query = graphql("repository_id_query", owner, name)
  local output = cli.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    mode = "sync",
  }
  local resp = vim.fn.json_decode(output)
  return resp.data.repository.id
end

---@param repo string
function M.util_get_repo_info(repo)
  local owner, name = utils.split_repo(repo)
  local query = graphql("repository_query", owner, name)
  return cli.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    mode = "sync",
  }
end

---@param repo string
function M.util_get_repo_templates(repo)
  local owner, name = utils.split_repo(repo)
  local query = graphql("repository_templates_query", owner, name)
  return cli.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    mode = "sync",
  }
end

---@param repo string
---@param commit string
---@param path string
---@param cb function
function M.util_get_file_contents(repo, commit, path, cb)
  local owner, name = utils.split_repo(repo)
  local query = graphql("file_content_query", owner, name, commit, path)

  cli.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
      elseif output then
        local resp = vim.fn.json_decode(output)
        local blob = resp.data.repository.object
        local lines = {}
        if blob and blob ~= vim.NIL and type(blob.text) == "string" then
          lines = vim.split(blob.text, "\n")
        end
        cb(lines)
      end
    end,
  }
end

---@param repo string
function M.util_fork(repo)
  utils.info(vim.fn.system('echo "n" | gh repo fork ' .. repo .. " 2>&1 | cat "))
end

---@param cb function
function M.util_get_pr_for_curr_branch(cb)
  cli.run {
    args = { "pr", "view", "--json", "id,number,headRepositoryOwner,headRepository,isCrossRepository,url" },
    cb = function(out)
      if out == "" then
        M.error "No pr found for current branch"
        return
      end
      local pr = vim.fn.json_decode(out)
      local owner
      local name
      if pr.number then
        if pr.isCrossRepository then
          -- Parsing the pr url is the only way to get the target repo owner if the pr is cross repo
          if not pr.url then
            M.error "Failed to get pr url"
            return
          end
          local url_suffix = pr.url:match "[^/]+/[^/]+/pull/%d+$"
          if not url_suffix then
            M.error "Failed to parse pr url"
            return
          end
          local iter = url_suffix:gmatch "[^/]+/"
          owner = vim.print(iter():sub(1, -2))
          name = vim.print(iter():sub(1, -2))
        else
          owner = pr.headRepositoryOwner.login
          name = pr.headRepository.name
        end
        local number = pr.number
        local id = pr.id
        local query = graphql("pull_request_query", owner, name, number, _G.octo_pv2_fragment)
        cli.run {
          args = { "api", "graphql", "--paginate", "--jq", ".", "-f", string.format("query=%s", query) },
          cb = function(output, stderr)
            if stderr and not utils.is_blank(stderr) then
              vim.api.nvim_err_writeln(stderr)
            elseif output then
              local resp = utils.aggregate_pages(output, "data.repository.pullRequest.timelineItems.nodes")
              local obj = resp.data.repository.pullRequest
              local Rev = require("octo.reviews.rev").Rev
              local PullRequest = require("octo.model.pull-request").PullRequest
              local pull_request = PullRequest:new {
                repo = owner .. "/" .. name,
                number = number,
                id = id,
                left = Rev:new(obj.baseRefOid),
                right = Rev:new(obj.headRefOid),
                files = obj.files.nodes,
              }
              cb(pull_request)
            end
          end,
        }
      end
    end,
  }
end

---@param login string
function M.util_get_user_id(login)
  local query = graphql("user_query", login)
  return cli.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    mode = "sync",
  }
end

---@param repo string
function M.util_get_label_id(repo)
  local owner, name = utils.split_repo(repo)
  local query = graphql("repo_labels_query", owner, name)
  return cli.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    mode = "sync",
  }
end

---@param remote_hostname string
function M.get_user_name(remote_hostname)
  return cli.get_user_name(remote_hostname)
end

return M
