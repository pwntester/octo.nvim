local octo = require "octo"
local gh = require "octo.gh"
local util = require "octo.util"
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
      M.get_issue(...)
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
      M.get_pull_request(...)
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
    files = function()
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
    reviews = function()
      M.pr_reviews()
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
      M.review_pr()
    end,
    comments = function()
      menu.review_comments()
    end,
    submit = function()
      M.submit_review()
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
      menu.gists(opts)
    end
  },
  comment = {
    add = function()
      M.add_comment()
    end,
    delete = function()
      M.delete_comment()
    end,
    resolve = function()
      M.resolve_comment()
    end,
    unresolve = function()
      M.unresolve_comment()
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

function table.pack(...)
  return {n = select("#", ...), ...}
end

function M.get_repo_number_from_varargs(...)
  local repo, number
  local args = table.pack(...)
  if args.n == 0 then
    print("Missing arguments")
    return
  elseif args.n == 1 then
    repo = util.get_remote_name()
    number = tonumber(args[1])
  elseif args.n == 2 then
    repo = args[1]
    number = tonumber(args[2])
  else
    print("Unexpected arguments")
    return
  end
  if not repo then
    print("Cant find repo name")
    return
  end
  if not number then
    print("Missing issue/pr number")
    return
  end
  return repo, number
end

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
    if not M.parse_url(object) then
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

function M.parse_url(url)
  local i, j, repo, number = string.find(url, "https://github.com/(.*)/issues/(%d+)")
  local type
  if not i then
    i, j, repo, number = string.find(url, "https://github.com/(.*)/pull/(%d+)")
    if i then
      type = "pull"
    end
  else
    type = "issue"
  end
  if repo and number then
    if "issue" == type then M.get_issue(repo, number); return true end
    if "pull" == type then M.get_pull_request(repo, number); return true end
  end
  return false
end

function M.add_comment()
  local bufnr = api.nvim_get_current_buf()
  local repo, _ = util.get_repo_number({"octo_issue", "octo_reviewthread"})
  if not repo then
    return
  end

  local comment = {
    createdAt = vim.fn.strftime("%FT%TZ"),
    author = {login = vim.g.octo_loggedin_user},
    body = " ",
    reactions = {
      totalCount = 0,
      nodes = {}
    },
    id = -1
  }
  writers.write_comment(bufnr, comment)
  vim.fn.execute("normal! Gkkk")
  vim.fn.execute("startinsert")
end

function M.delete_comment()
  local bufnr = api.nvim_get_current_buf()
  local repo, _ = util.get_repo_number({"octo_issue", "octo_reviewthread"})
  if not repo then
    return
  end
  local cursor = api.nvim_win_get_cursor(0)
  local comment, start_line, end_line = unpack(util.get_comment_at_cursor(bufnr, cursor))
  if not comment then
    print("The cursor does not seem to be located at any comment")
    return
  end
  local choice = vim.fn.confirm("Delete comment?", "&Yes\n&No\n&Cancel", 2)
  if choice == 1 then
    local kind = util.get_buffer_kind(bufnr)
    -- TODO: graphql
    gh.run(
      {
        args = {
          "api",
          "-X",
          "DELETE",
          format("repos/%s/%s/comments/%s", repo, kind, comment.id)
        },
        cb = function(_)
          api.nvim_buf_set_lines(bufnr, start_line - 2, end_line + 1, false, {})
          api.nvim_buf_clear_namespace(bufnr, comment.namespace, 0, -1)
          api.nvim_buf_clear_namespace(bufnr, constants.OCTO_REACTIONS_VT_NS, start_line - 2, end_line + 1)
          api.nvim_buf_del_extmark(bufnr, constants.OCTO_EM_NS, comment.extmark)
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
  local repo, _ = util.get_repo_number({"octo_reviewthread"})
  if not repo then
    return
  end
  local status, _, thread_id, comment_id =
    string.find(api.nvim_buf_get_name(bufnr), "octo://.*/pull/%d+/reviewthread/(.*)/comment/(.*)")
  if not status then
    api.nvim_err_writeln("Cannot extract thread id from buffer name")
    return
  end
  local query = format(graphql.resolve_review_mutation, thread_id)
  gh.run(
    {
      args = {"api", "graphql", "-f", format("query=%s", query)},
      cb = function(output, stderr)
        if stderr and not util.is_blank(stderr) then
          api.nvim_err_writeln(stderr)
        elseif output then
          local resp = json.parse(output)
          if resp.data.resolveReviewThread.thread.isResolved then
            local pattern = format("%s/%s", thread_id, comment_id)
            local qf = vim.fn.getqflist({items = 0})
            local items = qf.items
            for _, item in ipairs(items) do
              if item.pattern == pattern then
                item.text = string.gsub(item.text, "%) ", ") RESOLVED ", 1)
                break
              end
            end
            vim.fn.setqflist({}, "r", {items = items})
            print("RESOLVED!")
          end
        end
      end
    }
  )
end

function M.unresolve_comment()
  local bufnr = api.nvim_get_current_buf()
  local repo, _ = util.get_repo_number({"octo_reviewthread"})
  if not repo then
    return
  end
  local status, _, thread_id, comment_id =
    string.find(api.nvim_buf_get_name(bufnr), "octo://.*/pull/%d+/reviewthread/(.*)/comment/(.*)")
  if not status then
    api.nvim_err_writeln("Cannot extract thread id from buffer name")
    return
  end
  local query = format(graphql.unresolve_review_mutation, thread_id)
  gh.run(
    {
      args = {"api", "graphql", "-f", format("query=%s", query)},
      cb = function(output, stderr)
        if stderr and not util.is_blank(stderr) then
          api.nvim_err_writeln(stderr)
        elseif output then
          local resp = json.parse(output)
          if not resp.data.unresolveReviewThread.thread.isResolved then
            local pattern = format("%s/%s", thread_id, comment_id)
            local qf = vim.fn.getqflist({items = 0})
            local items = qf.items
            for _, item in ipairs(items) do
              if item.pattern == pattern then
                item.text = string.gsub(item.text, "RESOLVED ", "")
                break
              end
            end
            vim.fn.setqflist({}, "r", {items = items})
            print("UNRESOLVED!")
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
    query = format(graphql.update_issue_state_mutation, id, state)
  elseif type == "pull" then
    query = format(graphql.update_pull_request_state_mutation, id, state)
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
  local query = format(graphql.create_issue_mutation, repo_id, title, constants.NO_BODY_MSG)
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

function M.get_issue(...)
  local repo, number = M.get_repo_number_from_varargs(...)
  vim.cmd(format("edit octo://%s/issue/%s", repo, number))
end

function M.get_pull_request(...)
  local repo, number = M.get_repo_number_from_varargs(...)
  vim.cmd(format("edit octo://%s/pull/%s", repo, number))
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
          local _, bufnr = util.create_content_popup(lines)
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
  -- TODO: graphql
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

function M.pr_reviews()
  local repo, number, _ = util.get_repo_number_pr()
  if not repo then
    return
  end

  -- make sure CWD is in PR repo and branch
  if not util.in_pr_branch() then
    return
  end

  local owner = vim.split(repo, "/")[1]
  local name = vim.split(repo, "/")[2]
  local query = format(graphql.review_threads_query, owner, name, number)
  gh.run(
    {
      args = {"api", "graphql", "-f", format("query=%s", query)},
      --args = {"api", "graphql", "--paginate", "-f", format("query=%s", query)},
      cb = function(output, stderr)
        if stderr and not util.is_blank(stderr) then
          api.nvim_err_writeln(stderr)
        elseif output then
          -- aggregate comments
          -- local resp = util.aggregate_pages(output, "data.repository.pullRequest.reviewThreads.nodes.comments.nodes")
          -- for now, I will just remove pagination on this query since 100 comments in a single thread looks enough for most cases
          local resp = json.parse(output)
          reviews.populate_reviewthreads_qf(repo, number, resp.data.repository.pullRequest.reviewThreads.nodes)
        end
      end
    }
  )
end

function M.submit_review()
  local winnr, bufnr = util.create_popup({""}, {
    line = 5,
    col = 5,
    width = math.floor(vim.o.columns * 0.9),
    height = math.floor(vim.o.lines * 0.5)
  })
  api.nvim_set_current_win(winnr)

  local help_vt = {
    {"Press <c-a> to approve, <c-m> to comment or <c-r> to request changes", "OctoNvimDetailsValue"}
  }
  writers.write_block({"", "", ""}, {bufnr = bufnr, mark = false, line = 1})
  api.nvim_buf_set_virtual_text(bufnr, constants.OCTO_TITLE_VT_NS, 0, help_vt, {})
  local mapping_opts = {script = true, silent = true, noremap = true}
  api.nvim_buf_set_keymap(bufnr, "n", "q", format(":call nvim_win_close(%d, 1)<CR>", winnr), mapping_opts)
  api.nvim_buf_set_keymap(bufnr, "n", "<esc>", format(":call nvim_win_close(%d, 1)<CR>", winnr), mapping_opts)
  api.nvim_buf_set_keymap(bufnr, "n", "<C-c>", format(":call nvim_win_close(%d, 1)<CR>", winnr), mapping_opts)
  api.nvim_buf_set_keymap(bufnr, "n", "<C-a>", ":lua require'octo.reviews'.submit_review('APPROVE')<CR>", mapping_opts)
  api.nvim_buf_set_keymap(bufnr, "n", "<C-m>", ":lua require'octo.reviews'.submit_review('COMMENT')<CR>", mapping_opts)
  api.nvim_buf_set_keymap(bufnr, "n", "<C-r>", ":lua require'octo.reviews'.submit_review('REQUEST_CHANGES')<CR>", mapping_opts)
  vim.cmd [[normal G]]
  vim.cmd [[startinsert]]
end

function M.review_pr()
  local repo, number, pr = util.get_repo_number_pr()
  if not repo then
    return
  end
  if not vim.fn.exists("*fugitive#repo") then
    print("vim-fugitive required")
    return
  end
  -- make sure CWD is in PR repo and branch
  if not util.in_pr_branch() then
    return
  end

  reviews.review_comments = {}

  -- TODO: graphql
  -- get list of changed files
  local url = format("repos/%s/pulls/%d/files", repo, number)
  gh.run(
    {
      args = {"api", url},
      cb = function(output, stderr)
        if stderr and not util.is_blank(stderr) then
          api.nvim_err_writeln(stderr)
        elseif output then
          local results = json.parse(output)
          local changes = {}
          for _, result in ipairs(results) do
            local change = {
              filename = result.filename,
              patch = result.patch,
              status = result.status,
              stats = format("+%d -%d ~%d", result.additions, result.deletions, result.changes)
            }
            table.insert(changes, change)
          end
          reviews.populate_changes_qf(changes, {
            pull_request_id = pr.id,
            baseRefName = pr.baseRefName,
            baseRefSHA = pr.baseRefSHA,
            headRefName = pr.headRefName,
            headRefSHA = pr.headRefSHA
          })
        end
      end
    }
  )
end

function M.reaction_action(action, reaction)
  local bufnr = api.nvim_get_current_buf()

  local repo, number = util.get_repo_number({"octo_issue", "octo_reviewthread"})
  if not repo then
    return
  end

  local cursor = api.nvim_win_get_cursor(0)
  local comment = util.get_comment_at_cursor(bufnr, cursor)

  local url, args, line, cb_url, reactions

  if comment then
    -- found a comment at cursor
    local kind = util.get_buffer_kind(bufnr)
    comment = comment[1]
    cb_url = format("repos/%s/%s/comments/%d", repo, kind, comment.id)
    line = comment.reaction_line
    reactions = comment.reactions

    if action == "add" then
      url = format("repos/%s/%s/comments/%d/reactions", repo, kind, comment.id)
      args = {"api", "-X", "POST", "-f", format("content=%s", reaction), url}
    elseif action == "delete" then
      -- get list of reactions for issue comment and filter by user login and reaction
      -- TODO: graphql
      local output =
        gh.run(
        {
          mode = "sync",
          args = {"api", format("repos/%s/%s/comments/%d/reactions", repo, kind, comment.id)}
        }
      )
      for _, r in ipairs(json.parse(output)) do
        if r.user.login == vim.g.octo_loggedin_user and reaction == r.content then
          url = format("repos/%s/%s/comments/%d/reactions/%d", repo, kind, comment.id, r.id)
          args = {"api", "-X", "DELETE", url}
          break
        end
      end
    end
  elseif vim.bo.ft == "octo_issue" then
    -- cursor not located on a comment, using the issue instead
    cb_url = format("repos/%s/issues/%d", repo, number)
    reactions = api.nvim_buf_get_var(bufnr, "body_reactions")
    line = api.nvim_buf_get_var(bufnr, "body_reaction_line")
    if action == "add" then
      url = format("repos/%s/issues/%d/reactions", repo, number)
      args = {"api", "-X", "POST", "-f", format("content=%s", reaction), url}
    elseif action == "delete" then
      -- get list of reactions for issue comment and filter by user login and reaction
      local output =
        -- TODO: graphql
        gh.run(
        {
          mode = "sync",
          args = {"api", format("repos/%s/issues/%d/reactions", repo, number)}
        }
      )
      for _, r in ipairs(json.parse(output)) do
        if r.user.login == vim.g.octo_loggedin_user and reaction == r.content then
          url = format("repos/%s/issues/%d/reactions/%d", repo, number, r.id)
          args = {"api", "-X", "DELETE", url}
          break
        end
      end
    end
  end

  if not args or not cb_url then
    return
  end

  -- add/delete reaction
  -- TODO: graphql
  gh.run(
    {
      args = args,
      cb = function(output, stderr)
        if stderr and not util.is_blank(stderr) then
          api.nvim_err_writeln(stderr)
        elseif output then
          reaction = string.upper(reaction)
          if reaction == "+1" then
            reaction = "THUMBS_UP"
          elseif reaction == "-1" then
            reaction = "THUMBS_DOWN"
          end
          if action == "add" then
            table.insert(reactions.nodes, {content = reaction})
            reactions.totalCount = reactions.totalCount + 1
          elseif action == "delete" then
            for i, r in pairs(reactions.nodes) do
              if r.content == reaction then
                table.remove(reactions.nodes, i)
                break
              end
            end
            reactions.totalCount = reactions.totalCount - 1
          end

          -- update comment metadata with new reactions
          util.update_reactions_at_cursor(bufnr, cursor, reactions) --, line)

          -- refresh reactions
          writers.write_reactions(bufnr, reactions, line)
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
  menu.select_target_project_column(function(column_id)

    -- add new card
    local query = format(graphql.add_project_card_mutation, iid, column_id)
    gh.run(
      {
        args = {"api", "graphql", "--paginate", "-f", format("query=%s", query)},
        cb = function(output, stderr)
          if stderr and not util.is_blank(stderr) then
            api.nvim_err_writeln(stderr)
          elseif output then
            -- refresh issue/pr details
            octo.load(bufnr, function(obj)
              writers.write_details(bufnr, obj, true)
              api.nvim_buf_set_var(bufnr, "cards", obj.projectCards)
            end)
          end
        end
      }
    )
  end)

end

function M.delete_project_card()
  local bufnr = api.nvim_get_current_buf()
  local repo = util.get_repo_number()
  if not repo then
    return
  end

  -- show card selection menu
  menu.select_project_card(function(card)

    -- delete card
    local query = format(graphql.delete_project_card_mutation, card)
    gh.run(
      {
        args = {"api", "graphql", "--paginate", "-f", format("query=%s", query)},
        cb = function(output, stderr)
          if stderr and not util.is_blank(stderr) then
            api.nvim_err_writeln(stderr)
          elseif output then
            -- refresh issue/pr details
            octo.load(bufnr, function(obj)
              writers.write_details(bufnr, obj, true)
              api.nvim_buf_set_var(bufnr, "cards", obj.projectCards)
            end)
          end
        end
      }
    )
  end)
end

function M.move_project_card()
  local bufnr = api.nvim_get_current_buf()
  local repo = util.get_repo_number()
  if not repo then
    return
  end

  menu.select_project_card(function(source_card)

    -- show project column selection menu
    menu.select_target_project_column(function(target_column)

      -- move card to selected column
      local query = format(graphql.move_project_card_mutation, source_card, target_column)
      gh.run(
        {
          args = {"api", "graphql", "--paginate", "-f", format("query=%s", query)},
          cb = function(output, stderr)
            if stderr and not util.is_blank(stderr) then
              api.nvim_err_writeln(stderr)
            elseif output then
              -- refresh issue/pr details
              octo.load(bufnr, function(obj)
                writers.write_details(bufnr, obj, true)
                api.nvim_buf_set_var(bufnr, "cards", obj.projectCards)
              end)
            end
          end
        }
      )
    end)
  end)
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

  menu.select_label(function(label_id)

    local query = format(graphql.add_labels_mutation, iid, label_id)
    gh.run(
      {
        args = {"api", "graphql", "--paginate", "-f", format("query=%s", query)},
        cb = function(output, stderr)
          if stderr and not util.is_blank(stderr) then
            api.nvim_err_writeln(stderr)
          elseif output then
            -- refresh issue/pr details
            octo.load(bufnr, function(obj)
              writers.write_details(bufnr, obj, true)
            end)
          end
        end
      }
    )
  end)
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

  menu.select_assigned_label(function(label_id)

    local query = format(graphql.remove_labels_mutation, iid, label_id)
    gh.run(
      {
        args = {"api", "graphql", "--paginate", "-f", format("query=%s", query)},
        cb = function(output, stderr)
          if stderr and not util.is_blank(stderr) then
            api.nvim_err_writeln(stderr)
          elseif output then
            -- refresh issue/pr details
            octo.load(bufnr, function(obj)
              writers.write_details(bufnr, obj, true)
            end)
          end
        end
      }
    )
  end)
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

  menu.select_user(function(user_id)
    local query
    if subject == "assignee" then
      query = format(graphql.add_assignees_mutation, iid, user_id)
    elseif subject == "reviewer" then
      query = format(graphql.request_reviews_mutation, iid, user_id)
    end
    gh.run(
      {
        args = {"api", "graphql", "--paginate", "-f", format("query=%s", query)},
        cb = function(output, stderr)
          if stderr and not util.is_blank(stderr) then
            api.nvim_err_writeln(stderr)
          elseif output then
            -- refresh issue/pr details
            octo.load(bufnr, function(obj)
              writers.write_details(bufnr, obj, true)
            end)
          end
        end
      }
    )
  end)
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

  menu.select_assignee(function(user_id)
    local query = format(graphql.remove_assignees_mutation, iid, user_id)
    gh.run(
      {
        args = {"api", "graphql", "--paginate", "-f", format("query=%s", query)},
        cb = function(output, stderr)
          if stderr and not util.is_blank(stderr) then
            api.nvim_err_writeln(stderr)
          elseif output then
            -- refresh issue/pr details
            octo.load(bufnr, function(obj)
              writers.write_details(bufnr, obj, true)
            end)
          end
        end
      }
    )
  end)
end

return M
