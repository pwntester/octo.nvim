local octo = require "octo"
local gh = require "octo.gh"
local util = require "octo.util"
local menu = require "octo.menu"
local reviews = require "octo.reviews"
local constants = require("octo.constants")
local api = vim.api
local format = string.format
local json = {
  parse = vim.fn.json_decode
}
local Job = require("plenary.job")

local M = {}

local commands = {
  issue = {
    create = function(repo)
      M.create_issue(repo)
    end,
    edit = function(...)
      M.get_issue(...)
    end,
    close = function()
      M.change_issue_state("closed")
    end,
    open = function()
      M.change_issue_state("open")
    end,
    list = function(repo, ...)
      local rep, opts = M.process_varargs(repo, ...)
      menu.issues(rep, opts)
    end
  },
  pr = {
    edit = function(...)
      M.get_issue(...)
    end,
    list = function(repo, ...)
      local rep, opts = M.process_varargs(repo, ...)
      menu.pull_requests(rep, opts)
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
    end
  },
  review = {
    start = function()
      M.review_pr()
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
  comment = {
    add = function()
      M.add_comment()
    end,
    delete = function()
      M.delete_comment()
    end
  },
  label = {
    add = function(value)
      M.issue_action("add", "labels", value)
    end,
    delete = function(value)
      M.issue_action("delete", "labels", value)
    end
  },
  assignee = {
    add = function(value)
      M.issue_action("add", "assignees", value)
    end,
    delete = function(value)
      M.issue_action("delete", "assignees", value)
    end
  },
  reviewer = {
    add = function(value)
      M.issue_action("add", "reviewers", value)
    end,
    delete = function(value)
      M.issue_action("delete", "reviewers", value)
    end
  },
  reaction = {
    add = function(reaction)
      M.reaction_action("add", reaction)
    end,
    delete = function(reaction)
      M.reaction_action("delete", reaction)
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
  return repo, opts
end

function M.octo(object, action, ...)
  local o = commands[object]
  if not o then
    print("Incorrect argument, valid objects are:" .. vim.inspect(vim.tbl_keys(commands)))
    return
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
  local repo, _ = util.get_repo_number({"octo_issue", "octo_reviewthread"})
  if not repo then
    return
  end

  local comment = {
    created_at = vim.fn.strftime("%FT%TZ"),
    user = {login = vim.g.octo_loggedin_user},
    body = "",
    reactions = {total_count = 0},
    id = -1
  }
  octo.write_comment(bufnr, comment)
  --vim.fn.execute("normal! Gkkk")
  --vim.fn.execute("startinsert")
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

function M.change_issue_state(state)
  local bufnr = api.nvim_get_current_buf()
  local repo, number = util.get_repo_number()
  if not repo then
    return
  end

  if not state then
    api.nvim_err_writeln("Missing argument: state")
    return
  end

  gh.run(
    {
      args = {
        "api",
        "-X",
        "PATCH",
        "-f",
        format("state=%s", state),
        format("repos/%s/issues/%s", repo, number)
      },
      cb = function(output)
        local resp = json.parse(output)
        if state == resp["state"] then
          api.nvim_buf_set_var(bufnr, "state", resp["state"])
          octo.write_state(bufnr)
          octo.write_details(bufnr, resp, true)
          print("Issue state changed to: " .. resp["state"])
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
  gh.run(
    {
      args = {
        "api",
        "-X",
        "POST",
        "-f",
        format("title=%s", title),
        "-f",
        format("body=%s", constants.NO_BODY_MSG),
        format("repos/%s/issues", repo)
      },
      cb = function(output)
        octo.create_issue_buffer(json.parse(output), repo, true)
        vim.fn.execute("normal! Gkkk")
        vim.fn.execute("startinsert")
      end
    }
  )
end

function M.get_issue(...)
  local repo, number = M.get_repo_number_from_varargs(...)
  vim.cmd(format("edit octo://%s/%s", repo, number))
end

function M.issue_action(action, kind, value)
  local bufnr = api.nvim_get_current_buf()
  local repo, number = util.get_repo_number()
  if not repo then
    return
  end

  vim.validate {
    action = {
      action,
      function(a)
        return vim.tbl_contains({"add", "delete"}, a)
      end,
      "add or delete"
    },
    kind = {
      kind,
      function(a)
        return vim.tbl_contains({"assignees", "labels", "reviewers"}, a)
      end,
      "assignees, labels or reviewers"
    }
  }

  local endpoint
  if kind == "reviewers" then
    local _, _, pr = util.get_repo_number_pr()
    if not pr then
      return
    end
    endpoint = "pulls"
  else
    endpoint = "issues"
  end

  local url = format("repos/%s/%s/%d/%s", repo, endpoint, number, kind)
  if kind == "labels" and action == "delete" then
    url = format("%s/%s", url, value)
  elseif kind == "reviewers" then
    url = format("repos/%s/%s/%d/requested_reviewers", repo, endpoint, number)
  end

  local method
  if action == "add" then
    method = "POST"
  elseif action == "delete" then
    method = "DELETE"
  end

  -- gh does not allow array parameters at the moment
  -- workaround: https://github.com/cli/cli/issues/1484
  local cmd = format([[ jq -n '{"%s":["%s"]}' | gh api -X %s %s --input - ]], kind, value, method, url)
  local job =
    Job:new(
    {
      command = "sh",
      args = {"-c", cmd},
      on_exit = vim.schedule_wrap(
        function(jself, _, _)
          if jself:stderr_result() and not vim.tbl_isempty(jself:stderr_result()) then
            api.nvim_err_writeln(vim.inspect(jself:stderr_result()))
          end
          gh.run(
            {
              args = {"api", format("repos/%s/issues/%s", repo, number)},
              cb = function(output)
                octo.write_details(bufnr, json.parse(output), true)
              end
            }
          )
        end
      )
    }
  )
  job:start()
end

function M.checkout_pr()
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
        octo.write_state(bufnr)
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
          local lines = vim.split(output, "\n")
          table.insert(lines, "")
          local _, bufnr = util.create_content_popup(lines)
          local buf_lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
          for i, l in ipairs(buf_lines) do
            if #vim.split(l, "pass") > 1 then
              api.nvim_buf_add_highlight(bufnr, -1, "DiffAdd", i - 1, 0, -1)
            elseif #vim.split(l, "fail") > 1 then
              api.nvim_buf_add_highlight(bufnr, -1, "DiffDelete", i - 1, 0, -1)
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
        octo.write_state(bufnr)
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

function M.pr_reviews()
  local rep, number, _ = util.get_repo_number_pr()
  if not rep then
    return
  end

  -- make sure CWD is in PR repo and branch
  if not util.in_pr_branch() then
    return
  end

  local owner = vim.split(rep, "/")[1]
  local repo = vim.split(rep, "/")[2]
  local query =
    format(
    [[
    query($endCursor: String) {
      repository(owner:"%s", name:"%s") {
        pullRequest(number:%d){
           reviewThreads(last:80) {
              nodes{
                id,
                isResolved,
                isOutdated,
                path,
                line,
                resolvedBy { login },
                originalLine,
                startLine,
                originalStartLine,
                comments(first: 100, after: $endCursor) {
                  nodes{
                    id,
                    body,
                    author { login },
                    authorAssociation,
                    diffHunk,
                    reactions(last:50) {
                      totalCount,
                      nodes{
                        content
                      }
                    }
                  }
                  pageInfo {
                    hasNextPage
                    endCursor
                  }
                },
              }

          }
        }
      }
    }
  ]],
    owner,
    repo,
    number
  )
  gh.run(
    {
      args = {"api", "graphql", "--paginate", "-f", format("query=%s", query)},
      cb = function(output, stderr)
        if stderr and not util.is_blank(stderr) then
          api.nvim_err_writeln(stderr)
        elseif output then
          local resp = json.parse(output)
          reviews.populate_reviewthreads_qf(rep, number, resp.data.repository.pullRequest.reviewThreads.nodes)
        end
      end
    }
  )
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
              branch = pr.base.ref,
              filename = result.filename,
              status = result.status,
              text = format("+%d -%d", result.additions, result.deletions)
            }
            table.insert(changes, change)
          end
          reviews.populate_changes_qf(pr.base.ref, pr.head.ref, changes)
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
    comment = comment[1]
    cb_url = format("repos/%s/issues/comments/%d", repo, comment.id)
    line = comment.reaction_line
    reactions = comment.reactions
    local kind = util.get_buffer_kind(bufnr)
    if action == "add" then
      url = format("repos/%s/%s/comments/%d/reactions", repo, kind, comment.id)
      args = {"api", "-X", "POST", "-f", format("content=%s", reaction), url}
    elseif action == "delete" then
      -- get list of reactions for issue comment and filter by user login and reaction
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
    line = api.nvim_buf_get_var(bufnr, "reaction_line")
    reactions = api.nvim_buf_get_var(bufnr, "reactions")
    if action == "add" then
      url = format("repos/%s/issues/%d/reactions", repo, number)
      args = {"api", "-X", "POST", "-f", format("content=%s", reaction), url}
    elseif action == "delete" then
      -- get list of reactions for issue comment and filter by user login and reaction
      local output =
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
  gh.run(
    {
      args = args,
      cb = function(_)
        for k, v in pairs(reactions) do
          if k == reaction then
            if action == "add" then
              reactions[k] = v + 1
              reactions.total_count = reactions.total_count + 1
            elseif action == "delete" then
              reactions[k] = math.max(0, v - 1)
              reactions.total_count = reactions.total_count - 1
            end
            break
          end
        end
        util.update_reactions_at_cursor(bufnr, cursor, reactions, line)
        octo.write_reactions(bufnr, reactions, line)
      end
    }
  )
end

function M.issue_interactive_action(action, kind)
  vim.fn.inputsave()
  local value = vim.fn.input("Enter name: ")
  vim.fn.inputrestore()
  M.issue_action(action, kind, value)
end

return M
