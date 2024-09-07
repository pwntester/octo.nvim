local utils = require "octo.utils"
local cli = require "octo.backend.glab.cli"
local graphql = require "octo.backend.glab.graphql"
local converters = require "octo.backend.glab.converters"
local writers = require "octo.ui.writers"
local constants = require "octo.constants"

---Discussions are the glab timeline WITHOUT LabelEvents, Closed/OpenedEvents and Pending Notes.
---@param iid string
---@return glab_discussion[]
local function fetch_mr_discussions(iid)
  local url_discussions = string.format("/projects/:id/merge_requests/%s/discussions", iid)
  -- #244
  -- local result = utils.aggregate_pages(output, X)
  local output = cli.run {
    args = { "api", url_discussions },
    mode = "sync",
  }
  return vim.fn.json_decode(output)
end

---@param iid string
---@return glab_note[]
local function fetch_mr_pending_notes(iid)
  local url_pending_notes = string.format("/projects/:id/merge_requests/%s/draft_notes", iid)
  -- #244
  local output = cli.run {
    args = { "api", url_pending_notes },
    mode = "sync",
  }
  return vim.fn.json_decode(output)
end

---Gitlab needs extra requests to resemble the graphql gh api.
---discussions, pending_notes, labelevents, and state events
---@param iid string
---@param own_name string
---@return glab_discussion[]
local function fetch_mr_all_discussions(iid, own_name)
  local discussions = fetch_mr_discussions(iid)

  local pending_notes = fetch_mr_pending_notes(iid)
  local author = { ["login"] = own_name, ["name"] = own_name, ["username"] = own_name, ["isViewer"] = true }
  -- #233 fetch emojis via graphql
  for _, note in pairs(pending_notes) do
    local converted_note = converters.convert_pending_note_to_thread_comment(note, author)

    if note.discussion_id ~= vim.NIL then
      local found_thread = false
      for _, discussion in ipairs(discussions) do
        if discussion.id == note.discussion_id then
          table.insert(discussion.notes, converted_note)
          found_thread = true
          break
        end
      end
      if not found_thread then
        utils.error "Found no thread to attach pending note to!"
      end
    else
      -- Temporary discussion_id of "-{note_id}". Need an unique ID anyways.
      -- Need to differentiate if the as a whole is pending. See buffer_update_comment.
      -- Could think about adding 'state' to thread_metadata or so.
      table.insert(discussions, {
        ["id"] = "-" .. note.id,
        ["notes"] = { [1] = converted_note },
      })
    end
  end

  return discussions
end

---@param iid integer
---@return glab_diff
local function fetch_mr_diff(iid)
  local url = string.format("/projects/:id/merge_requests/%d/diffs?unidiff=true", iid)
  local output = cli.run {
    -- #244: endpoint doesnt support the default per_page of 100, so it needs the extra `?per_page=30`
    args = { "api", url },
    mode = "sync",
  }
  return vim.fn.json_decode(output)
end

---@param file FileEntry
---@param diffSide "LEFT"|"RIGHT
---@param left_linenr integer
---@param right_linenr integer
---@return boolean
local function is_diff_line_unchanged(file, diffSide, left_linenr, right_linenr)
  local comment_ranges, line
  if diffSide == "RIGHT" then
    line = right_linenr
    comment_ranges = file.right_comment_ranges
  elseif diffSide == "LEFT" then
    line = left_linenr
    comment_ranges = file.left_comment_ranges
  end

  local diffhunk
  local diffhunks = file.diffhunks
  for i, range in ipairs(comment_ranges) do
    if range[1] <= line and range[2] >= line then
      diffhunk = diffhunks[i]
      break
    end
  end
  if not vim.startswith(diffhunk, "@@") then
    diffhunk = "@@ " .. diffhunk
  end
  local map = utils.generate_line2position_map(diffhunk)

  local position
  if diffSide == "RIGHT" then
    position = map.right_side_lines[tostring(line)]
  elseif diffSide == "LEFT" then
    position = map.left_side_lines[tostring(line)]
  end
  --  Parse the diffHunk if the line is added or not
  local diff_lines = vim.split(diffhunk, "\n")
  local relevant_line = diff_lines[position]

  -- Check the Diff line for whitespace aka the absence of '-' or '+'
  return string.sub(relevant_line, 1, 1) == " "
end

---@param review Review
---@param comment_metadata CommentMetadata
---@param is_multiline boolean
---@return string
local function create_draft_notes_query(review, comment_metadata, is_multiline)
  local thread_file
  for _, file in ipairs(review.layout.files) do
    if file.path == comment_metadata.path then
      thread_file = file
    end
  end

  -- Comments on unchanged lines require both line positions.
  local position_query
  local left_linenr = vim.api.nvim__buf_stats(thread_file.left_bufid)["current_lnum"]
  local right_linenr = vim.api.nvim__buf_stats(thread_file.right_bufid)["current_lnum"]
  local is_unchanged = is_diff_line_unchanged(thread_file, comment_metadata.diffSide, left_linenr, right_linenr)
  if comment_metadata.diffSide == "LEFT" then
    position_query = string.format("position[old_line]=%s", comment_metadata.snippetStartLine)
    if is_unchanged then
      position_query = position_query .. string.format("&position[new_line]=%s", right_linenr)
    end
  else
    position_query = string.format("position[new_line]=%s", comment_metadata.snippetStartLine)
    if is_unchanged then
      position_query = position_query .. string.format("&position[old_line]=%s", left_linenr)
    end
  end

  local query = string.format(
    "note=%s&position[base_sha]=%s&position[start_sha]=%s&position[head_sha]=%s&position[old_path]=%s&position[new_path]=%s&position[position_type]=text&",
    comment_metadata.body,
    thread_file.pull_request.left.commit,
    thread_file.pull_request.left.commit,
    thread_file.pull_request.right.commit,
    comment_metadata.path, -- #234 only if not deleted
    comment_metadata.path
  )
  query = query .. position_query

  return utils.url_encode(query)
end

local M = {}

---<Return> on Octo pr list
---@param repo string
---@param kind string
---@param number integer
---@param cb function
function M.load(repo, kind, number, cb)
  local query, global_id

  if kind == "pull" then
    global_id = string.format("gid://gitlab/MergeRequest/%s", number)
    query = graphql("pull_request_query", global_id)
  elseif kind == "issue" then
    -- #233
    utils.error "glab doesn't have <load issue> implemented"
    return
  elseif kind == "repo" then
    -- #233
    utils.error "glab doesn't have <load repo> implemented"
    return
  end

  cli.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        vim.api.nvim_err_writeln(stderr)
      elseif output then
        local result = vim.fn.json_decode(output)
        local converted_pull_request = converters.convert_graphql_pull_request(result.data.mergeRequest)
        local iid = tostring(converted_pull_request.number)
        local own_name = cli.get_user_name()
        local discussions = fetch_mr_all_discussions(iid, own_name)

        -- #233 MergedEvent, ClosedEvent, ReopenedEvent
        -- glab api "/projects/:id/merge_requests/:iid/resource_state_events"

        -- #233 LabeledEvent, UnlabeledEvent
        -- glab api "/projects/:id/merge_requests/:iid/resource_label_events"

        converted_pull_request.timelineItems = converters.convert_discussions_to_threads(discussions, own_name)

        local threads = {}
        for _, discussion in ipairs(discussions) do
          local thread_header = discussion.notes[1]
          -- and not thread_header.resolved
          if thread_header.type == "DiffNote" then
            table.insert(threads, converters.convert_discussion_to_reviewthreads(discussion, own_name))
          end
        end
        converted_pull_request.reviewThreads.nodes = threads

        cb(converted_pull_request)
      end
    end,
  }
end

---This command deletes comment.id aka one note of a thread
---@param comment CommentMetadata
---@param buffer OctoBuffer
---@param bufnr integer
function M.cmds_delete_comment(comment, buffer, bufnr)
  local start_line = comment.bufferStartLine
  local end_line = comment.bufferEndLine

  local threadId, url
  if comment.kind == "IssueComment" then
    -- #233 Comment without Diff
    utils.error "glab doesn't have <delete IssueComment> implemented"
    return
  elseif comment.kind == "PullRequestReview" then
    -- #233 what exactly is this state?
    utils.error "glab doesn't have <delete PullRequestReview> implemented"
    return
  elseif comment.kind == "PullRequestReviewComment" then
    local _thread = buffer:get_thread_at_cursor()
    threadId = _thread.threadId
    if comment.state == "PENDING" then
      url = string.format("/projects/:id/merge_requests/%s/draft_notes/%s", buffer.number, comment.id)
      if not vim.startswith(tostring(threadId), "-") then
        threadId = "-" .. threadId
      end
    else
      url =
        string.format("/projects/:id/merge_requests/%s/discussions/%s/notes/%d", buffer.number, threadId, comment.id)
    end
  end

  if vim.fn.confirm("Delete comment?", "&Yes\n&No\n&Cancel", 2) ~= 1 then
    return
  end

  -- #234 this call has no response, so no need for this cb structure, right?
  cli.run {
    args = { "api", "--method", "DELETE", url },
    cb = function(_)
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
        -- timeline doesnt need an additional update in the backend
        local review = require("octo.reviews").get_current_review()
        if review then
          -- Gitlab doesnt return the global state of reviewThreads,
          -- so we need to fetch it from the buffer.
          -- review.threads is a table indexable by the discussion_id,
          -- so we can just delete that index off review.threads.
          -- BUT: update_threads expects a table indexed by natural numbers 1,2,3,4 etc.
          if review.threads[threadId].discussion_id ~= vim.NIL then
            for k, note in pairs(review.threads[threadId].comments.nodes) do
              if note.id == comment.id then
                review.threads[threadId].comments.nodes[k] = nil
              end
            end
          end

          local thread_was_deleted = false
          if
            review.threads[threadId].discussion_id ~= vim.NIL
            or not review.threads[threadId].comments.nodes
            or vim.tbl_isempty(review.threads[threadId].comments.nodes)
          then
            thread_was_deleted = true
            review.threads[threadId] = nil
          end

          local temp_reviews = {}
          local i = 1
          for _, thread in pairs(review.threads) do
            temp_reviews[i] = thread
            i = i + 1
          end

          review:update_threads(temp_reviews)
          buffer:render_signs()

          if thread_was_deleted then
            -- this was the last comment, close the thread buffer
            -- No comments left
            utils.error("Deleting buffer " .. tostring(bufnr))
            local bufname = vim.api.nvim_buf_get_name(bufnr)
            local split = string.match(bufname, "octo://.+/review/[^/]+/threads/([^/]+)/.*")
            if split then
              local layout = require("octo.reviews").get_current_review().layout
              local file = layout:cur_file()
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
      end
    end,
  }
end

---@param bufnr integer
---@param thread gh_thread
---@param thread_line integer
local function update_review_thread_header(bufnr, thread, thread_line)
  -- update thread header resolved state
  local start_line = thread.originalStartLine ~= vim.NIL and thread.originalStartLine or thread.originalLine
  local end_line = thread.originalLine
  writers.write_review_thread_header(bufnr, {
    path = thread.path,
    start_line = start_line,
    end_line = end_line,
    -- glab response only contains the updated thread, so no need to iterate
    commit = thread.comments.nodes[1].originalCommit.abbreviatedOid,
    isOutdated = thread.isOutdated,
    isResolved = thread.isResolved,
    resolvedBy = { login = vim.g.octo_viewer },
  }, thread_line - 2)

  local review = require("octo.reviews").get_current_review()
  if review then
    local new_threads = {}
    local i = 1
    for _, review_thread in pairs(review.threads) do
      new_threads[i] = review_thread
      if review_thread.id == thread.id then
        review_thread.isResolved = not review_thread.isResolved
      end
      i = i + 1
    end
    review:update_threads(new_threads)
  end
end

---@param thread ThreadMetadata
---@param bufnr integer
---@param number integer MR IID
function M.cmds_resolve_thread(thread, bufnr, number)
  local thread_id = thread.threadId
  local thread_line = thread.bufferStartLine

  local url = string.format("/projects/:id/merge_requests/%s/discussions/%s?resolved=true", number, thread_id)

  cli.run {
    args = { "api", "--method", "PUT", url },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
      elseif output then
        local discussion = vim.fn.json_decode(output)
        local own_name = cli.get_user_name()
        local resp_thread = converters.convert_discussion_to_reviewthreads(discussion, own_name)
        if resp_thread.isResolved then
          update_review_thread_header(bufnr, resp_thread, thread_line)
        end
        -- vim.cmd(string.format("%d,%dfoldclose", thread_line, thread_line))
      end
    end,
  }
end

---@param thread ThreadMetadata
---@param bufnr integer
---@param number integer MR IID
function M.cmds_unresolve_thread(thread, bufnr, number)
  local thread_id = thread.threadId
  local thread_line = thread.bufferStartLine

  local url = string.format("/projects/:id/merge_requests/%s/discussions/%s?resolved=false", number, thread_id)

  cli.run {
    args = { "api", "--method", "PUT", url },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
      elseif output then
        local discussion = vim.fn.json_decode(output)
        local own_name = cli.get_user_name()
        local resp_thread = converters.convert_discussion_to_reviewthreads(discussion, own_name)
        if not resp_thread.isResolved then
          update_review_thread_header(bufnr, resp_thread, thread_line)
        end
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
  local project_path = buffer.repo

  local query = graphql("create_label_mutation", project_path, name, description, color)
  cli.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
      elseif output then
        local resp = vim.fn.json_decode(output)
        local label = resp.data.labelCreate.label
        utils.info("Created label: " .. label.title)

        -- refresh issue/pr details
        local gid = string.match(buffer.node.global_id, constants.GID_MR_PATTERN)
        require("octo").load(buffer.repo, buffer.kind, gid, function(obj)
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
  local query = graphql("set_labels_mutation", iid, label_id, "APPEND", buffer.repo)
  cli.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
      elseif output then
        -- refresh issue/pr details
        local gid = string.match(buffer.node.global_id, constants.GID_MR_PATTERN)
        require("octo").load(buffer.repo, buffer.kind, gid, function(obj)
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
  local operation_mode = "REMOVE"
  local project_path = buffer.repo
  local query = graphql("set_labels_mutation", iid, label_id, operation_mode, project_path)

  cli.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
      elseif output then
        -- refresh issue/pr details
        local gid = string.match(buffer.node.global_id, constants.GID_MR_PATTERN)
        require("octo").load(buffer.repo, buffer.kind, gid, function(obj)
          writers.write_details(bufnr, obj, true)
        end)
      end
    end,
  }
end

---Add repo contributors #233 Placeholder
---@param repo string
---@param users table
function M.buffer_fetch_taggable_users(repo, users) end

---Fetches the issues in the repo so they can be used for completion. #233 Placeholder
---@param repo string
function M.buffer_fetch_issues(repo) end

---@param buffer OctoBuffer
---@param id string
---@param title_metadata TitleMetadata
---@param desc_metadata BodyMetadata
function M.buffer_save_title_and_body(buffer, id, title_metadata, desc_metadata)
  local project_path = buffer.repo
  local query
  -- #233 Issues
  if buffer:isIssue() then
    utils.error "glab doesn't have <update Issue body> implemented"
  elseif buffer:isPullRequest() then
    query = graphql("merge_request_update_mutation", id, project_path, title_metadata.body, desc_metadata.body)
  end

  cli.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
      elseif output then
        local resp = vim.fn.json_decode(output)
        local obj
        if buffer:isPullRequest() then
          obj = resp.data.mergeRequestUpdate.mergeRequest
        -- #233 Issues
        elseif buffer:isIssue() then
          utils.error "glab doesn't have <update Issue body> implemented"
        end
        if title_metadata.body == obj.title then
          title_metadata.savedBody = obj.title
          title_metadata.dirty = false
          buffer.titleMetadata = title_metadata
        end

        if desc_metadata.body == obj.description then
          desc_metadata.savedBody = obj.description
          desc_metadata.dirty = false
          buffer.bodyMetadata = desc_metadata
        end

        buffer:render_signs()
        utils.info "Saved!"
      end
    end,
  }
end

---Create new, pending thread reply.
---Gitlab doesnt seem to support two pending comments via api to the same comment,
---and the error isnt even correct json, so the glab cli tool fails to unmarshal it :D?
---@param buffer OctoBuffer
---@param comment_metadata CommentMetadata
function M.buffer_add_thread_comment(buffer, comment_metadata)
  -- #234 Unclear why its ["1"] and not [1].
  -- There should be a better way to fetch the thread_id, but the usual buffer:get_threadid stuff doesnt work.
  local threadId = buffer.threadsMetadata["1"].threadId
  local query = string.format("note=%s&in_reply_to_discussion_id=%s", comment_metadata.body, threadId)
  local encoded_query = utils.url_encode(query)
  local url = string.format("/projects/:id/merge_requests/%d/draft_notes?%s", buffer.number, encoded_query)

  cli.run {
    args = { "api", "--method", "POST", url },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        vim.api.nvim_err_writeln(stderr)
      elseif output then
        local new_note = vim.fn.json_decode(output)
        new_note.body = new_note.note
        new_note.resolved = false
        new_note.state = "PENDING"
        local own_name = cli.get_user_name()
        new_note.author = { ["login"] = own_name, ["name"] = own_name, ["username"] = own_name }
        -- gitlab just doesnt send those:
        -- new_note.created_at | new_note.updated_at

        local comment_end
        if utils.trim(comment_metadata.body) == utils.trim(new_note.note) then
          local comments = buffer.commentsMetadata
          for i, c in ipairs(comments) do
            if tonumber(c.id) == -1 then
              comments[i].id = new_note.id
              comments[i].savedBody = new_note.body
              comments[i].dirty = false
              comment_end = comments[i].endLine
              break
            end
          end

          local review = require("octo.reviews").get_current_review()
          local new_threads = {}
          local i = 1
          for _, thread in pairs(review.threads) do
            new_threads[i] = thread
            if thread.id == threadId then
              local converted_new_note =
                converters.convert_note_to_reviewthread(new_note, own_name, thread.comments.nodes[1].diffHunk, threadId)
              table.insert(new_threads[i].comments.nodes, converted_new_note)
            end
            i = i + 1
          end

          if review then
            review:update_threads(new_threads)
          end

          buffer:render_signs()

          -- update thread map
          local mark_id
          for markId, threadMetadata in pairs(buffer.threadsMetadata) do
            if threadMetadata.threadId == threadId then
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

---Basic without code suggestion
---@param buffer OctoBuffer
---@param comment_metadata CommentMetadata
---@param review Review
---@param is_multiline boolean
function M.buffer_pr_add_thread(buffer, comment_metadata, review, is_multiline)
  local encoded_query = create_draft_notes_query(review, comment_metadata, is_multiline)
  local url = string.format("/projects/:id/merge_requests/%d/draft_notes?%s", buffer.number, encoded_query)

  cli.run {
    args = { "api", "--method", "POST", url },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        vim.api.nvim_err_writeln(stderr)
      elseif output then
        local new_note = vim.fn.json_decode(output)
        new_note.body = new_note.note
        new_note.resolved = false
        new_note.state = "PENDING"
        local own_name = cli.get_user_name()
        new_note.author = { ["login"] = own_name, ["name"] = own_name, ["username"] = own_name }
        -- gitlab just doesnt send those:
        -- new_note.created_at | new_note.updated_at

        -- Temporary discussion_id of "-{note_id}". Need an unique ID anyways.
        -- The minus shows if the thread as a whole is pending. See buffer_update_comment
        local discussion = { ["id"] = "-" .. new_note.id, ["notes"] = { [1] = new_note } }
        local converted_resp = converters.convert_discussion_to_reviewthreads(discussion, own_name)

        if not utils.is_blank(converted_resp) then
          local new_comment = converted_resp.comments.nodes[1]
          local comments = buffer.commentsMetadata
          for i, c in ipairs(comments) do
            if tonumber(c.id) == -1 then
              comments[i].id = new_comment.id
              comments[i].savedBody = new_comment.body
              comments[i].dirty = false
              break
            end
          end
          -- I dont understand how the gh variant doesnt need this.
          -- This doesnt get updated anywhere else, so a review refresh is necessary for a lot of operations.
          local buffer_threads = buffer.threadsMetadata
          for k, c in pairs(buffer_threads) do
            if tonumber(c.threadId) == -1 then
              buffer_threads[k].threadId = new_comment.id
              break
            end
          end
          -- Gitlab doesnt return the global state of reviewThreads,
          -- so we need to fetch it from the buffer.
          -- review.threads is a table indexed by the discussion_id,
          -- which results in a problem when using ipairs further
          -- down the line to iterate over the threads in a buffer.
          -- -> minimal invasive workaround (#234)
          local temp_reviews = {}
          local i = 1
          for _, thread in pairs(review.threads) do
            temp_reviews[i] = thread
            i = i + 1
          end
          temp_reviews[i] = converted_resp
          if review then
            review:update_threads(temp_reviews)
          end
          buffer:render_signs()
        else
          utils.error "Failed to create thread"
          return
        end
      end
    end,
  }
end

---Review: update a note
---@param buffer OctoBuffer
---@param comment_metadata CommentMetadata
function M.buffer_update_comment(buffer, comment_metadata)
  local url, threadId

  if comment_metadata.kind == "IssueComment" then
    -- #233 Comment without Diff
    utils.error "glab doesn't have <update IssueComment> implemented"
  elseif comment_metadata.kind == "PullRequestReview" then
    -- #233 what exactly is this state?
    utils.error "glab doesn't have <update PullRequestReview> implemented"
  elseif comment_metadata.kind == "PullRequestReviewComment" then
    local _thread = buffer:get_thread_at_cursor()
    threadId = _thread.threadId

    -- Different queries based upon pending and/or attachment to an existing thread
    if comment_metadata.state == "PENDING" then
      local encoded_query
      if string.sub(threadId, 1, 1) == "-" then
        local review = require("octo.reviews").get_current_review()
        local is_multiline = _thread.bufferStartLine == _thread.bufferEndLine
        encoded_query = create_draft_notes_query(review, comment_metadata, is_multiline)
      else
        local query = string.format("note=%s&in_reply_to_discussion_id=%s", comment_metadata.body, threadId)
        encoded_query = utils.url_encode(query)
      end
      url = string.format(
        "/projects/:id/merge_requests/%d/draft_notes/%d?%s",
        buffer.number,
        comment_metadata.id,
        encoded_query
      )
    else
      local encoded_body_query = utils.url_encode(comment_metadata.body)
      url = string.format(
        "/projects/:id/merge_requests/%s/discussions/%s/notes/%d?body=%s",
        buffer.number,
        threadId,
        comment_metadata.id,
        encoded_body_query
      )
    end
  end

  cli.run {
    args = { "api", "--method", "PUT", url },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        vim.api.nvim_err_writeln(stderr)
      elseif output then
        local resp = vim.fn.json_decode(output)
        local updated_body
        if comment_metadata.state == "PENDING" then
          updated_body = resp.note
        else
          updated_body = resp.body
        end
        if comment_metadata.kind == "IssueComment" then
          -- #233 Comment without Diff
          utils.error "glab doesn't have <update IssueComment> implemented"
        elseif comment_metadata.kind == "PullRequestReview" then
          -- #233 what exactly is this state?
          utils.error "glab doesn't have <update PullRequestReview> implemented"
        elseif comment_metadata.kind == "PullRequestReviewComment" then
          local review = require("octo.reviews").get_current_review()
          if review then
            -- Gitlab doesnt return the global state of reviewThreads,
            -- so we need to fetch it from the buffer.
            -- review.threads is a table indexable by the discussion_id,
            -- so we can just delete that index off review.threads.
            -- BUT: update_threads expects a table indexed by natural numbers 1,2,3,4 etc.
            for k, note in pairs(review.threads[threadId].comments.nodes) do
              if note.id == comment_metadata.id then
                review.threads[threadId].comments.nodes[k].body = utils.trim(updated_body)
              end
            end

            local temp_reviews = {}
            local i = 1
            for _, thread in pairs(review.threads) do
              temp_reviews[i] = thread
              i = i + 1
            end

            review:update_threads(temp_reviews)
          end
        end

        if updated_body and utils.trim(comment_metadata.body) == utils.trim(updated_body) then
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
  local diffs = fetch_mr_diff(number)
  local aggregated_diffs = ""
  for _, diff in pairs(diffs) do
    aggregated_diffs = aggregated_diffs .. diff.diff
  end

  return aggregated_diffs
end

---@param base string
---@param pattern string
---@return integer
local function count(base, pattern)
  return select(2, string.gsub(base, pattern, ""))
end

---@param diff string
---@return integer, integer, integer
local function generate_summary_from_diff(diff)
  -- somehow these newlines arent explicit within the lua string, so no need to escape lol.
  local additions = count(diff, "\n%+")
  local deletions = count(diff, "\n%-")

  return additions, deletions, additions + deletions
end

---@param pr PullRequest
---@param cb function
function M.pr_get_changed_files(pr, cb)
  local url = string.format("/projects/:id/merge_requests/%d/diffs", pr.number)
  cli.run {
    -- #244: endpoint doesnt support the default per_page of 100, so it needs the extra `?per_page=30`
    args = { "api", url },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
      elseif output then
        local FileEntry = require("octo.reviews.file-entry").FileEntry
        ---@type glab_diff[]
        local results = vim.fn.json_decode(output)
        local files = {}
        for _, result in ipairs(results) do
          local additions, deletions, changes = generate_summary_from_diff(result.diff)
          local entry = FileEntry:new {
            path = result.new_path,
            previous_path = result.old_path,
            patch = result.diff,
            pull_request = pr,
            status = converters.convert_file_status(result),
            stats = {
              additions = additions,
              deletions = deletions,
              changes = changes,
            },
          }
          table.insert(files, entry)
        end
        cb(files)
      end
    end,
  }
end

---Fetches notes and draft notes. Filters resolved discussions.
---@param pr_id string
function M.review_start_review_mutation(pr_id, cb)
  local own_name = cli.get_user_name()
  local discussions = fetch_mr_all_discussions(pr_id, own_name)

  local threads = {}
  for _, discussion in ipairs(discussions) do
    local thread_header = discussion.notes[1]
    -- and not thread_header.resolved
    if thread_header.type == "DiffNote" then
      table.insert(threads, converters.convert_discussion_to_reviewthreads(discussion, own_name))
    end
  end
  cb {
    ["data"] = {
      ["addPullRequestReview"] = {
        ["pullRequestReview"] = {
          ["id"] = pr_id,
          ["state"] = "PENDING", -- CHANGES_REQUESTED, APPROVED, COMMENTED
          ["pullRequest"] = {
            ["reviewThreads"] = {
              ["nodes"] = threads,
            },
          },
        },
      },
    },
  }
end

---Post all pending notes and optionally write a comment+change review state
---@param id integer
---@param layout Layout
---@param event string
function M.review_submit(id, layout, event)
  local winid = vim.api.nvim_get_current_win()
  local bufnr = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local body = utils.escape_char(utils.trim(table.concat(lines, "\n")))
  local state_cmd = converters.convert_event_to_glab_cmd(event)

  local url = string.format("/projects/:id/merge_requests/%s/draft_notes/bulk_publish", id)
  cli.run {
    args = { "api", "--method", "POST", url },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
      elseif output then
        if body and body ~= "" then
          cli.run {
            args = { "mr", "note", id, "-m", body },
            mode = "sync",
          }
        end
        if state_cmd then
          local stdout, _ = cli.run {
            args = { "mr", state_cmd, id },
            mode = "sync",
          }
          utils.info(stdout)
        end
        utils.info "Review was submitted successfully!"
        pcall(vim.api.nvim_win_close, winid, 0)
        layout:close()
      end
    end,
  }
end

---WARNING: Untested
---Due to needing to pull anyway to fetch the actual diff of the MR,
---there is no way to currently test this
---@param repo string
---@param commit string
---@param path string
---@param cb function
function M.util_get_file_contents(repo, commit, path, cb)
  local url = string.format("/projects/:id/repository/files/%s/raw?ref=%s", path, commit)

  cli.run {
    args = { "api", url },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        -- if the file got added or deleted within this MR, this answer is expected.
        if string.find(stderr, "404 File Not Found") then
          cb { [1] = "" }
        end
        utils.error(stderr)
      elseif output then
        local lines = {}
        if output and output ~= vim.NIL then
          lines = vim.split(output, "\n")
        end
        cb(lines)
      end
    end,
  }
end

---@param remote_hostname string
function M.get_user_name(remote_hostname)
  return cli.get_user_name(remote_hostname)
end

return M
