local OctoBuffer = require'octo.model.octo-buffer'.OctoBuffer
local gh = require "octo.gh"
local signs = require "octo.signs"
local constants = require "octo.constants"
local config = require "octo.config"
local colors = require'octo.colors'
local util = require "octo.util"
local graphql = require "octo.graphql"
local writers = require "octo.writers"
local window = require "octo.window"
local reviews = require "octo.reviews"
require "octo.completion"
require "octo.folds"

local M = {}

_G.octo_repo_issues = {}
_G.octo_buffers = {}

function M.init()
  colors.setup()
end

function M.setup(user_config)
  signs.setup()
  config.setup(user_config or {})
  M.check_login()
end

function M.configure_octo_buffer(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local split, path = util.get_split_and_path(vim.api.nvim_buf_get_name(bufnr))
  if split and path then
    -- review diff buffers
    local current_review = reviews.get_current_review()
    if current_review and #current_review.threads > 0 then
      current_review.layout:cur_file():place_signs()
    end
  else
    -- issue/pr/reviewthread buffers
    local buffer = octo_buffers[bufnr]
    buffer:configure()
  end
end

function M.save_buffer()
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  buffer:save()
end

function M.load_buffer(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local bufname = vim.fn.bufname(bufnr)
  local repo, type, number = string.match(bufname, "octo://(.+)/(.+)/(%d+)")
  if not repo or not type or not number then
    vim.api.nvim_err_writeln("Incorrect buffer: " .. bufname)
    return
  end
  M.load(bufnr, function(obj)
    M.create_buffer(type, obj, repo, false)
  end)
end

function M.load(bufnr, cb)
  local bufname = vim.fn.bufname(bufnr)
  local repo, kind, number = string.match(bufname, "octo://(.+)/(.+)/(%d+)")
  if not repo or not kind or not number then
    vim.api.nvim_err_writeln("Incorrect buffer: " .. bufname)
    return
  end
  local owner, name = util.split_repo(repo)
  local query, key
  if kind == "pull" then
    query = graphql("pull_request_query", owner, name, number)
    key = "pullRequest"
  elseif kind == "issue" then
    query = graphql("issue_query", owner, name, number)
    key = "issue"
  end
  gh.run(
    {
      args = {"api", "graphql", "--paginate", "-f", string.format("query=%s", query)},
      cb = function(output, stderr)
        if stderr and not util.is_blank(stderr) then
          vim.api.nvim_err_writeln(stderr)
        elseif output then
          local resp = util.aggregate_pages(output, string.format("data.repository.%s.timelineItems.nodes", key))
          local obj = resp.data.repository[key]
          cb(obj)
        end
      end
    }
  )
end

function M.render_signcolumn()
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  buffer:render_signcolumn()
end

function M.on_cursor_hold()
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer then return end

  -- reactions popup
  local id = util.reactions_at_cursor()
  if id then
    local query = graphql("reactions_for_object_query", id)
    gh.run(
      {
        args = {"api", "graphql", "-f", string.format("query=%s", query)},
        cb = function(output, stderr)
          if stderr and not util.is_blank(stderr) then
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

  -- user popup
  local login = util.extract_pattern_at_cursor(constants.USER_PATTERN)
  if login then
    local query = graphql("user_profile_query", login)
    gh.run(
      {
        args = {"api", "graphql", "-f", string.format("query=%s", query)},
        cb = function(output, stderr)
          if stderr and not util.is_blank(stderr) then
            vim.api.nvim_err_writeln(stderr)
          elseif output then
            local resp = vim.fn.json_decode(output)
            local user = resp.data.user
            local popup_bufnr = vim.api.nvim_create_buf(false, true)
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

  -- link popup
  local repo, number = util.extract_pattern_at_cursor(constants.LONG_ISSUE_PATTERN)
  if not repo or not number then
    repo = buffer.repo
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
      args = {"api", "graphql", "-f", string.format("query=%s", query)},
      cb = function(output, stderr)
        if stderr and not util.is_blank(stderr) then
          vim.api.nvim_err_writeln(stderr)
        elseif output then
          local resp = vim.fn.json_decode(output)
          local issue = resp.data.repository.issueOrPullRequest
          local popup_bufnr = vim.api.nvim_create_buf(false, true)
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
    vim.api.nvim_err_writeln(string.format("Cannot find issue in %s", repo))
    return
  end

  local bufnr
  if create then
    bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.cmd(string.format("file octo://%s/%s/%d", repo, type, obj.number))
  else
    bufnr = vim.api.nvim_get_current_buf()
  end

  --vim.api.nvim_set_current_buf(bufnr)

  local octo_buffer = OctoBuffer:new({
    bufnr = bufnr,
    number = obj.number,
    repo = repo,
    node = obj
  })

  octo_buffer:configure()
  octo_buffer:render_issue()
  octo_buffer:async_fetch_taggable_users()
  octo_buffer:async_fetch_issues()
end

-- function M.check_editable()
--   local bufnr = vim.api.nvim_get_current_buf()
--
--   local body = util.get_body_at_cursor(bufnr)
--   if body and body.viewerCanUpdate then
--     return
--   end
--
--   local comment = util.get_comment_at_cursor(bufnr)
--   if comment and comment.viewerCanUpdate then
--     return
--   end
--
--   local key = vim.api.nvim_replace_termcodes("<esc>", true, false, true)
--   vim.api.nvim_feedkeys(key, "m", true)
--   print("[Octo] Cannot make changes to non-editable regions")
-- end

function M.check_login()
  local _, err = gh.run(
    {
      args = {"auth", "status"},
      mode = "sync"
    }
  )
  local name = string.match(err, "Logged in to [^%s]+ as ([^%s]+)")
  if name then
    vim.g.octo_viewer = name
    return name
  end
end

return M
