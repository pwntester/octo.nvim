local gh = require "octo.gh"
local signs = require "octo.signs"
local constants = require "octo.constants"
local util = require "octo.util"
local graphql = require "octo.graphql"
local writers = require "octo.writers"
local date = require "octo.date"
local vim = vim
local api = vim.api
local format = string.format
local json = {
  parse = vim.fn.json_decode,
  stringify = vim.fn.json_encode
}

local M = {}

function M.check_login()
  gh.run(
    {
      args = {"auth", "status"},
      cb = function(_, err)
        local _, _, name = string.find(err, "Logged in to [^%s]+ as ([^%s]+)")
        vim.g.octo_loggedin_user = name
      end
    }
  )
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
  local owner = vim.split(repo, "/")[1]
  local name = vim.split(repo, "/")[2]
  local query, key
  if type == "pull" then
    query = format(graphql.pull_request_query, owner, name, number)
    key = "pullRequest"
  elseif type == "issue" then
    query = format(graphql.issue_query, owner, name, number)
    key = "issue"
  end
  gh.run(
    {
      args = {"api", "graphql", "--paginate", "-f", format("query=%s", query)},
      cb = function(output, stderr)
        if stderr and not util.is_blank(stderr) then
          api.nvim_err_writeln(stderr)
        elseif output then
          local resp = util.aggregate_pages(output, format("data.repository.%s.comments.nodes", key))
          local obj = resp.data.repository[key]
            cb(obj)
        end
      end
    }
  )
end

-- This function accumulates all the taggable users into a single list that
-- gets set as a buffer variable `taggable_users`. If this list of users
-- is needed syncronously, this function will need to be refactored.
-- The list of taggable users should contain:
--   - The PR author
--   - The authors of all the existing comments
--   - The contributors of the repo
local function async_fetch_taggable_users(bufnr, repo, participants)
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
local function async_fetch_issues(bufnr, repo)
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

  -- clear buffer
  api.nvim_buf_set_lines(bufnr, 0, -1, false, {})

  -- delete extmarks
  for _, m in ipairs(api.nvim_buf_get_extmarks(bufnr, constants.OCTO_EM_NS, 0, -1, {})) do
    api.nvim_buf_del_extmark(bufnr, constants.OCTO_EM_NS, m[1])
  end

  -- configure buffer
  api.nvim_buf_set_option(bufnr, "filetype", "octo_issue")
  api.nvim_buf_set_option(bufnr, "buftype", "acwrite")

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
  local reaction_line = writers.write_reactions(bufnr, obj.reactions, api.nvim_buf_line_count(bufnr) - 1)
  api.nvim_buf_set_var(bufnr, "body_reactions", obj.reactions)
  api.nvim_buf_set_var(bufnr, "body_reaction_line", reaction_line)

  -- collect comments
  api.nvim_buf_set_var(bufnr, "comments", {})
  local comments = obj.comments.nodes

  if obj.commits then

    -- collect review comments
    if obj.reviews then
      vim.list_extend(comments, obj.reviews.nodes)
    end

    -- for pulls, store some additional info
    api.nvim_buf_set_var(
      bufnr,
      "pr",
      {
        id = obj.id,
        isDraft = obj.isDraft,
        merged = obj.merged,
        headRefName = obj.headRefName,
        headRefSHA = obj.headRefOid,
        baseRefName = obj.baseRefName,
        baseRefSHA = obj.baseRefOid,
        baseRepoName = obj.baseRepository.nameWithOwner
      }
    )
  end

  -- sort comments
  table.sort(comments, function (c1, c2)
    return date(c1.createdAt) < date(c2.createdAt)
  end)

  -- write comments
  for _, c in ipairs(comments) do
    writers.write_comment(bufnr, c)
  end

  async_fetch_taggable_users(bufnr, repo, obj.participants.nodes)
  async_fetch_issues(bufnr, repo)

  -- show signs
  signs.render_signcolumn(bufnr)

  -- drop undo history
  vim.fn["octo#clear_history"]()

  -- reset modified option
  api.nvim_buf_set_option(bufnr, "modified", false)

  vim.cmd [[ augroup octo_buffer_autocmds ]]
  vim.cmd [[ au! * <buffer> ]]
  vim.cmd [[ au TextChanged <buffer> lua require"octo.signs".render_signcolumn() ]]
  vim.cmd [[ au TextChangedI <buffer> lua require"octo.signs".render_signcolumn() ]]
  vim.cmd [[ augroup END ]]
end

function M.save_buffer()
  local bufnr = api.nvim_get_current_buf()
  local ft = api.nvim_buf_get_option(bufnr, "filetype")
  local repo, number = util.get_repo_number({"octo_issue", "octo_reviewthread"})
  if not repo then
    return
  end

  -- collect comment metadata
  util.update_issue_metadata(bufnr)

  -- title & description
  if ft == "octo_issue" then
    local title_metadata = api.nvim_buf_get_var(bufnr, "title")
    local desc_metadata = api.nvim_buf_get_var(bufnr, "description")
    if title_metadata.dirty or desc_metadata.dirty then
      -- trust but verify
      if string.find(title_metadata.body, "\n") then
        api.nvim_err_writeln("Title can't contains new lines")
        return
      elseif title_metadata.body == "" then
        api.nvim_err_writeln("Title can't be blank")
        return
      end

      -- TODO: graphql
      gh.run(
        {
          args = {
            "api",
            "-X",
            "PATCH",
            "-f",
            format("title=%s", title_metadata.body),
            "-f",
            format("body=%s", desc_metadata.body),
            format("repos/%s/issues/%s", repo, number)
          },
          cb = function(output)
            local resp = json.parse(output)

            if title_metadata.body == resp.title then
              title_metadata.saved_body = resp.title
              title_metadata.dirty = false
              api.nvim_buf_set_var(bufnr, "title", title_metadata)
            end

            if desc_metadata.body == resp.body then
              desc_metadata.saved_body = resp.body
              desc_metadata.dirty = false
              api.nvim_buf_set_var(bufnr, "description", desc_metadata)
            end

            signs.render_signcolumn(bufnr)
            print("Saved!")
          end
        }
      )
    end
  end

  -- comments
  local kind, post_url
  if ft == "octo_issue" then
    kind = "issues"
    post_url = format("repos/%s/%s/%d/comments", repo, kind, number)
  elseif ft == "octo_reviewthread" then
    kind = "pulls"
    local status, _, comment_id =
      string.find(api.nvim_buf_get_name(bufnr), "octo://.*/pull/%d+/reviewthread/.*/comment/(.*)")
    if not status then
      api.nvim_err_writeln("Cannot extract comment id from buffer name")
      return
    end
    post_url = format("/repos/%s/pulls/%d/comments/%s/replies", repo, number, comment_id)
  end

  local comments = api.nvim_buf_get_var(bufnr, "comments")
  for _, metadata in ipairs(comments) do
    if metadata.body ~= metadata.saved_body then
      if metadata.id == -1 then
        -- create new comment/reply
        -- TODO: graphql
        gh.run(
          {
            args = {
              "api",
              "-X",
              "POST",
              "-f",
              format("body=%s", metadata.body),
              post_url
            },
            cb = function(output, stderr)
              if stderr and not util.is_blank(stderr) then
                api.nvim_err_writeln(stderr)
              elseif output then
                local resp = json.parse(output)
                if vim.fn.trim(metadata.body) == vim.fn.trim(resp.body) then
                  for i, c in ipairs(comments) do
                    if tonumber(c.id) == -1 then
                      comments[i].id = resp.id
                      comments[i].saved_body = resp.body
                      comments[i].dirty = false
                      break
                    end
                  end
                  api.nvim_buf_set_var(bufnr, "comments", comments)
                  signs.render_signcolumn(bufnr)
                  print("Saved!")
                end
              end
            end
          }
        )
      else
        -- update comment/reply
        gh.run(
          {
            args = {
              "api",
              "-X",
              "PATCH",
              "-f",
              format("body=%s", metadata.body),
              format("repos/%s/%s/comments/%d", repo, kind, metadata.id)
            },
            cb = function(output, stderr)
              if stderr and not util.is_blank(stderr) then
                api.nvim_err_writeln(stderr)
              elseif output then
                local resp = json.parse(output)
                if vim.fn.trim(metadata.body) == vim.fn.trim(resp.body) then
                  for i, c in ipairs(comments) do
                    if tonumber(c.id) == tonumber(resp.id) then
                      comments[i].saved_body = resp.body
                      comments[i].dirty = false
                      break
                    end
                  end
                  api.nvim_buf_set_var(bufnr, "comments", comments)
                  signs.render_signcolumn(bufnr)
                  print("Saved!")
                end
              end
            end
          }
        )
      end
    end
  end

  -- reset modified option
  api.nvim_buf_set_option(bufnr, "modified", false)
end

function M.apply_buffer_mappings(bufnr, kind)
  local mapping_opts = {script = true, silent = true, noremap = true}

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
  end

  if kind == "pull" then
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
      [[<cmd>lua require'octo.commands'.issue_interactive_action('add', 'reviewers')<CR>]],
      mapping_opts
    )
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      "<space>vd",
      [[<cmd>lua require'octo.commands'.issue_interactive_action('delete', 'reviewers')<CR>]],
      mapping_opts
    )
  end

  if kind == "issue" or kind == "pull" then
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      "<space>la",
      [[<cmd>lua require'octo.commands'.issue_interactive_action('add', 'labels')<CR>]],
      mapping_opts
    )
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      "<space>ld",
      [[<cmd>lua require'octo.commands'.issue_interactive_action('delete', 'labels')<CR>]],
      mapping_opts
    )

    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      "<space>aa",
      [[<cmd>lua require'octo.commands'.issue_interactive_action('add', 'assignees')<CR>]],
      mapping_opts
    )
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      "<space>ad",
      [[<cmd>lua require'octo.commands'.issue_interactive_action('delete', 'assignees')<CR>]],
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
      [[<cmd>lua require'octo.commands'.reaction_action('add', 'hooray')<CR>]],
      mapping_opts
    )
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      "<space>rh",
      [[<cmd>lua require'octo.commands'.reaction_action('add', 'heart')<CR>]],
      mapping_opts
    )
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      "<space>re",
      [[<cmd>lua require'octo.commands'.reaction_action('add', 'eyes')<CR>]],
      mapping_opts
    )
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      "<space>r+",
      [[<cmd>lua require'octo.commands'.reaction_action('add', '+1')<CR>]],
      mapping_opts
    )
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      "<space>r-",
      [[<cmd>lua require'octo.commands'.reaction_action('add', '-1')<CR>]],
      mapping_opts
    )
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      "<space>rr",
      [[<cmd>lua require'octo.commands'.reaction_action('add', 'rocket')<CR>]],
      mapping_opts
    )
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      "<space>rl",
      [[<cmd>lua require'octo.commands'.reaction_action('add', 'laugh')<CR>]],
      mapping_opts
    )
    api.nvim_buf_set_keymap(
      bufnr,
      "n",
      "<space>rc",
      [[<cmd>lua require'octo.commands'.reaction_action('add', 'confused')<CR>]],
      mapping_opts
    )
  end
end

return M
