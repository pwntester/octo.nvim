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
local cmd = vim.cmd
local format = string.format
local json = {
  parse = vim.fn.json_decode,
}

local M = {
  settings = {
    mappings = {}
  }
}

function M.setup(opts)
  opts = opts or {}
  opts.mappings = opts.mappings or {}

  -- commands
  if vim.fn.executable('gh') then
    cmd [[command! -complete=customlist,v:lua.octo_command_complete -nargs=* Octo lua require"octo.commands".octo(<f-args>)]]
    cmd [[command! -range OctoAddReviewComment lua require"octo.reviews".add_review_comment(false)]]
    cmd [[command! -range OctoAddReviewSuggestion lua require"octo.reviews".add_review_comment(true)]]
  else
    print("[Octo] Cannot find `gh` command.")
  end

-- autocommands
  cmd [[augroup octo_autocmds]]
  cmd [[au!]]
  cmd [[au BufEnter octo://* lua require'octo'.configure_octo_buffer()]]
  cmd [[au BufReadCmd octo://* lua require'octo'.load_buffer()]]
  cmd [[au BufWriteCmd octo://* lua require'octo'.save_buffer()]]
  cmd [[au CursorHold octo://* lua require'octo'.on_cursor_hold()]]
  cmd [[au CursorHold octo://* lua require'octo.reviews'.show_review_threads()]]
  cmd [[au CursorMoved octo://* lua require'octo.reviews'.clear_review_threads()]]
  cmd [[augroup END]]

  -- sign definitions
  cmd [[sign define octo_thread text= texthl=OctoNvimBlue]]
  cmd [[sign define octo_thread_resolved text=  texthl=OctoNvimGreen]]
  cmd [[sign define octo_thread_outdated text=  texthl=OctoNvimRed]]
  cmd [[sign define octo_thread_pending text= texthl=OctoNvimYellow]]
  cmd [[sign define octo_thread_resolved_pending text= texthl=OctoNvimYellow]]
  cmd [[sign define octo_thread_outdated_pending text= texthl=OctoNvimYellow]]

  cmd [[sign define octo_comment_range numhl=OctoNvimGreen]]
  cmd [[sign define octo_clean_block_start text=┌ linehl=OctoNvimEditable]]
  cmd [[sign define octo_clean_block_end text=└ linehl=OctoNvimEditable]]
  cmd [[sign define octo_dirty_block_start text=┌ texthl=OctoNvimDirty linehl=OctoNvimEditable]]
  cmd [[sign define octo_dirty_block_end text=└ texthl=OctoNvimDirty linehl=OctoNvimEditable]]
  cmd [[sign define octo_dirty_block_middle text=│ texthl=OctoNvimDirty linehl=OctoNvimEditable]]
  cmd [[sign define octo_clean_block_middle text=│ linehl=OctoNvimEditable]]
  cmd [[sign define octo_clean_line text=[ linehl=OctoNvimEditable]]
  cmd [[sign define octo_dirty_line text=[ texthl=OctoNvimDirty linehl=OctoNvimEditable]]

  -- highlight group definitions
  cmd [[highlight default OctoNvimViewer guifg=#000000 guibg=#58A6FF]]
  cmd [[highlight default OctoNvimBubbleGreen guibg=#238636 guifg=#acf2bd]]
  cmd [[highlight default OctoNvimBubbleRed guibg=#da3633 guifg=#fdb8c0]]
  cmd [[highlight default OctoNvimBubblePurple guifg=#ffffff guibg=#6f42c1]]
  cmd [[highlight default OctoNvimBubbleYellow guibg=#735c0f guifg=#d3c846 ]]
  cmd [[highlight default OctoNvimBubbleBlue guifg=#eaf5ff guibg=#0366d6]]
  cmd [[highlight default OctoNvimGreen guifg=#238636]]
  cmd [[highlight default OctoNvimRed guifg=#da3633]]
  cmd [[highlight default OctoNvimPurple guifg=#ad7cfd]]
  cmd [[highlight default OctoNvimYellow guifg=#d3c846]]
  cmd [[highlight default OctoNvimBlue guifg=#58A6FF]]
  cmd [[highlight default link OctoNvimDirty OctoNvimRed]]
  cmd [[highlight default link OctoNvimIssueId Question]]
  cmd [[highlight default link OctoNvimIssueTitle PreProc]]
  cmd [[highlight default link OctoNvimEmpty Comment]]
  cmd [[highlight default link OctoNvimFloat NormalFloat]]
  cmd [[highlight default link OctoNvimTimelineItemHeading Comment]]
  cmd [[highlight default link OctoNvimSymbol Comment]]
  cmd [[highlight default link OctoNvimDate Comment]]
  cmd [[highlight default link OctoNvimDetailsLabel Title ]]
  cmd [[highlight default link OctoNvimDetailsValue Identifier]]
  cmd [[highlight default link OctoNvimMissingDetails Comment]]
  cmd [[highlight default link OctoNvimEditable NormalFloat]]
  cmd [[highlight default link OctoNvimBubble NormalFloat]]
  cmd [[highlight default link OctoNvimUser OctoNvimBubble]]
  cmd [[highlight default link OctoNvimUserViewer OctoNvimViewer]]
  cmd [[highlight default link OctoNvimReaction OctoNvimBubble]]
  cmd [[highlight default link OctoNvimReactionViewer OctoNvimViewer]]
  cmd [[highlight default link OctoNvimPassingTest OctoNvimGreen]]
  cmd [[highlight default link OctoNvimFailingTest OctoNvimRed]]
  cmd [[highlight default link OctoNvimPullAdditions OctoNvimGreen ]]
  cmd [[highlight default link OctoNvimPullDeletions OctoNvimRed ]]
  cmd [[highlight default link OctoNvimPullModifications OctoNvimBlue]]
  cmd [[highlight default link OctoNvimStateOpen OctoNvimGreen]]
  cmd [[highlight default link OctoNvimStateClosed OctoNvimRed]]
  cmd [[highlight default link OctoNvimStateMerged OctoNvimPurple]]
  cmd [[highlight default link OctoNvimStatePending OctoNvimYellow]]
  cmd [[highlight default link OctoNvimStateApproved OctoNvimStateOpen]]
  cmd [[highlight default link OctoNvimStateChangesRequested OctoNvimStateClosed]]
  cmd [[highlight default link OctoNvimStateCommented Normal]]
  cmd [[highlight default link OctoNvimStateDismissed OctoNvimStateClosed]]
  cmd [[highlight default link OctoNvimStateSubmitted OctoNvimBubbleGreen]]

  -- folds
  require'octo.folds'

  -- logged-in user
  if not vim.g.octo_viewer then
    M.check_login()
  end

  -- settings
  M.settings = {
    date_format = opts.date_format or "%Y %b %d %I:%M %p %Z";
    default_remote = opts.default_remote or {"upstream", "origin"};
    qf_height = opts.qf_height or 11;
    reaction_viewer_hint_icon = opts.icon_reaction_viewer_hint or "";
    user_icon = opts.user_icon or " ";
    right_bubble_delimiter = opts.right_bubble_delimiter or "";
    left_bubble_delimiter = opts.left_bubble_delimiter or "";
    github_hostname = opts.github_hostname or "";
    snippet_context_lines = opts.snippet_context_lines or 4;
    mappings = {
      reload = opts.mappings.reload or "<C-r>";
      open_in_browser = opts.mappings.open_in_browser or "<C-o>";
      goto_issue = opts.mappings.goto_issue or "<space>gi";
      close = opts.mappings.close or "<space>ic";
      reopen = opts.mappings.reopen or "<space>io";
      list_issues = opts.mappings.list_issues or "<space>il";
      list_commits = opts.mappings.list_commits or "<space>pc";
      list_changed_files = opts.mappings.list_changed_files or "<space>pf";
      show_pr_diff = opts.mappings.show_pr_diff or "<space>pd";
      checkout_pr = opts.mappings.checkout_pr or "<space>po";
      merge_pr = opts.mappings.merge_pr or "<space>pm";
      add_reviewer = opts.mappings.add_reviewer or "<space>va";
      remove_reviewer = opts.mappings.remove_reviewer or "<space>vd";
      add_assignee = opts.mappings.add_assignee or "<space>aa";
      remove_assignee = opts.mappings.remove_assignee or "<space>ad";
      add_label = opts.mappings.add_label or "<space>la";
      remove_label = opts.mappings.remove_label or "<space>ld";
      add_comment = opts.mappings.add_comment or "<space>ca";
      delete_comment = opts.mappings.delete_comment or "<space>cd";
      add_suggestion = opts.mappings.add_comment or "<space>sa";
      react_hooray = opts.mappings.react_hooray or "<space>rp";
      react_heart = opts.mappings.react_heart or "<space>rh";
      react_eyes = opts.mappings.react_eyes or "<space>re";
      react_thumbs_up = opts.mappings.react_thumbs_up or "<space>r+";
      react_thumbs_down = opts.mappings.react_thumbs_down or "<space>r-";
      react_rocket = opts.mappings.rocket or "<space>rr";
      react_laugh = opts.mappings.react_laugh or "<space>rl";
      react_confused = opts.mappings.react_confused or "<space>rc";
      next_changed_file = opts.mappings.next_changed_file or "]q";
      prev_change_file = opts.mappings.prev_change_file or "[q";
      next_comment = opts.mappings.next_comment or "]c";
      prev_comment = opts.mappings.prev_comment or "[c";
      next_thread = opts.mappings.next_thread or "]t";
      prev_thread = opts.mappings.prev_thread or "[t";
      close_tab = opts.mappings.close_tab or "<C-c>";
    }
  }

  vim.g.loaded_octo = true
end

function _G.octo_command_complete(argLead, cmdLine)
  local command_keys = vim.tbl_keys(require"octo.commands".commands)
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
    local o = require"octo.commands".commands[parts[2]]
    if not o then
      return
    end
    return get_options(vim.tbl_keys(o))
  end
end

function _G.octo_omnifunc(findstart, base)
  -- :help complete-functions
  if findstart == 1 then
    -- findstart
    local line = api.nvim_get_current_line()
    local pos = vim.fn.col(".")

    local start, finish = 0, 0
    while true do
      start, finish = string.find(line, "#(%d*)", start + 1)
      if start and pos > start and pos <= finish + 1 then
        return start - 1
      elseif not start then
        break
      end
    end

    start, finish = 0, 0
    while true do
      start, finish = string.find(line, "@(%w*)", start + 1)
      if start and pos > start and pos <= finish + 1 then
        return start - 1
      elseif not start then
        break
      end
    end

    return -2
  elseif findstart == 0 then
    local entries = {}
    if vim.startswith(base, "@") then
      local users = api.nvim_buf_get_var(0, "taggable_users") or {}
      for _, user in pairs(users) do
        table.insert(entries, {word = format("@%s", user), abbr = user})
      end
    else
      if vim.startswith(base, "#") then
        local issues = api.nvim_buf_get_var(0, "issues") or {}
        for _, i in ipairs(issues) do
          if vim.startswith("#" .. tostring(i.number), base) then
            table.insert(
              entries,
              {
                abbr = tostring(i.number),
                word = format("#%d", i.number),
                menu = i.title
              }
            )
          end
        end
      end
    end
    return entries
  end
end

function _G.octo_foldtext()
  return "..."
end

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
      vim.cmd [[setlocal omnifunc=v:lua.octo_omnifunc]]
      vim.cmd [[setlocal conceallevel=2]]
      vim.cmd [[setlocal signcolumn=yes]]
      vim.cmd [[setlocal foldenable]]
      vim.cmd [[setlocal foldtext=v:lua.octo_foldtext()]]
      vim.cmd [[setlocal foldmethod=manual]]
      vim.cmd [[setlocal foldcolumn=3]]
      vim.cmd [[setlocal foldlevelstart=99]]
      vim.cmd [[setlocal nonumber norelativenumber nocursorline wrap]]
      vim.cmd [[setlocal fillchars=fold:⠀,foldopen:⠀,foldclose:⠀,foldsep:⠀]]

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
            require"octo.reviews".update_qf()
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
            require"octo.reviews".update_qf()
            require"octo.reviews".update_thread_signs()
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
            require"octo.reviews".update_qf()
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
  util.clear_history()

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
      M.settings.mappings.close,
      [[<cmd>lua require'octo.commands'.change_issue_state('closed')<CR>]],
      mapping_opts
    )
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      M.settings.mappings.reopen,
      [[<cmd>lua require'octo.commands'.change_issue_state('open')<CR>]],
      mapping_opts
    )

    local repo_ok, repo = pcall(api.nvim_buf_get_var, bufnr, "repo")
    if repo_ok then
      api.nvim_buf_set_keymap(
        bufnr,
        "n",
        M.settings.mappings.list_issues,
        format("<cmd>lua require'octo.menu'.issues('%s')<CR>", repo),
        mapping_opts
      )
    end
  elseif kind == "pull" then
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      M.settings.mappings.checkout_pr,
      [[<cmd>lua require'octo.commands'.checkout_pr()<CR>]],
      mapping_opts
    )
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      M.settings.mappings.list_commits,
      [[<cmd>lua require'octo.menu'.commits()<CR>]],
      mapping_opts
    )
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      M.settings.mappings.list_changed_files,
      [[<cmd>lua require'octo.menu'.files()<CR>]],
      mapping_opts
    )
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      M.settings.mappings.show_pr_diff,
      [[<cmd>lua require'octo.commands'.show_pr_diff()<CR>]],
      mapping_opts
    )
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      M.settings.mappings.merge_pr,
      [[<cmd>lua require'octo.commands'.merge_pr("commit")<CR>]],
      mapping_opts
    )
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      M.settings.mappings.add_reviewer,
      [[<cmd>lua require'octo.commands'.add_user('reviewer')<CR>]],
      mapping_opts
    )
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      M.settings.mappings.remove_reviewer,
      [[<cmd>lua require'octo.commands'.remove_user('reviewer')<CR>]],
      mapping_opts
    )
  end

  if kind == "issue" or kind == "pull" then
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      M.settings.mappings.reload,
      [[<cmd>lua require'octo.commands'.reload()<CR>]],
      mapping_opts
    )
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      M.settings.mappings.open_in_browser,
      [[<cmd>lua require'octo.navigation'.open_in_browser()<CR>]],
      mapping_opts
    )
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      M.settings.mappings.add_label,
      [[<cmd>lua require'octo.commands'.add_label()<CR>]],
      mapping_opts
    )
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      M.settings.mappings.remove_label,
      [[<cmd>lua require'octo.commands'.delete_label()<CR>]],
      mapping_opts
    )
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      M.settings.mappings.add_assignee,
      [[<cmd>lua require'octo.commands'.add_user('assignee')<CR>]],
      mapping_opts
    )
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      M.settings.mappings.remove_assignee,
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
      M.settings.mappings.goto_issue,
      [[<cmd>lua require'octo.navigation'.go_to_issue()<CR>]],
      mapping_opts
    )
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      M.settings.mappings.next_comment,
      [[<cmd>lua require'octo'.next_comment()<CR>]],
      mapping_opts
    )
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      M.settings.mappings.prev_comment,
      [[<cmd>lua require'octo'.prev_comment()<CR>]],
      mapping_opts
    )

    -- comments
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      M.settings.mappings.add_comment,
      [[<cmd>lua require'octo.commands'.add_comment()<CR>]],
      mapping_opts
    )

    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      M.settings.mappings.delete_comment,
      [[<cmd>lua require'octo.commands'.delete_comment()<CR>]],
      mapping_opts
    )

    -- reactions
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      M.settings.mappings.react_hooray,
      [[<cmd>lua require'octo.commands'.reaction_action('hooray')<CR>]],
      mapping_opts
    )
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      M.settings.mappings.react_heart,
      [[<cmd>lua require'octo.commands'.reaction_action('heart')<CR>]],
      mapping_opts
    )
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      M.settings.mappings.react_eyes,
      [[<cmd>lua require'octo.commands'.reaction_action('eyes')<CR>]],
      mapping_opts
    )
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      M.settings.mappings.react_thumbs_up,
      [[<cmd>lua require'octo.commands'.reaction_action('+1')<CR>]],
      mapping_opts
    )
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      M.settings.mappings.react_thumbs_down,
      [[<cmd>lua require'octo.commands'.reaction_action('-1')<CR>]],
      mapping_opts
    )
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      M.settings.mappings.react_rocket,
      [[<cmd>lua require'octo.commands'.reaction_action('rocket')<CR>]],
      mapping_opts
    )
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      M.settings.mappings.react_laugh,
      [[<cmd>lua require'octo.commands'.reaction_action('laugh')<CR>]],
      mapping_opts
    )
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      M.settings.mappings.react_confused,
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
