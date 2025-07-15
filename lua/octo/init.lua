local OctoBuffer = require("octo.model.octo-buffer").OctoBuffer
local autocmds = require "octo.autocmds"
local config = require "octo.config"
local constants = require "octo.constants"
local commands = require "octo.commands"
local completion = require "octo.completion"
local folds = require "octo.folds"
local gh = require "octo.gh"
local queries = require "octo.gh.queries"
local graphql = require "octo.gh.graphql"
local picker = require "octo.picker"
local reviews = require "octo.reviews"
local signs = require "octo.ui.signs"
local window = require "octo.ui.window"
local colors = require "octo.ui.colors"
local writers = require "octo.ui.writers"
local utils = require "octo.utils"
local vim = vim

---@type table<string, { number: integer, title: string }[]>
_G.octo_repo_issues = {}
---@type table<integer, OctoBuffer>
_G.octo_buffers = {}

local M = {}

function M.setup(user_config)
  if not vim.fn.has "nvim-0.7" then
    utils.error "octo.nvim requires neovim 0.7+"
    return
  end

  config.setup(user_config or {})
  if not vim.fn.executable(config.values.gh_cmd) then
    utils.error("gh executable not found using path: " .. config.values.gh_cmd)
    return
  end

  colors.setup()
  signs.setup()
  picker.setup()
  completion.setup()
  folds.setup()
  autocmds.setup()
  commands.setup()
  gh.setup()
end

function M.update_layout_for_current_file()
  local bufnr = vim.api.nvim_get_current_buf()
  local thisfile = vim.api.nvim_buf_get_name(bufnr)
  local relative_path = vim.fn.fnamemodify(thisfile, ":~:.")
  local review = reviews.get_current_review()
  if review == nil then
    return
  end
  local files = review.layout.files
  for _, file in ipairs(files) do
    if file.path == relative_path then
      review.layout:set_current_file(file)
      vim.api.nvim_set_current_win(review.layout.right_winid)
    end
  end
end

function M.configure_octo_buffer(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local split, path = utils.get_split_and_path(bufnr)
  local buffer = octo_buffers[bufnr]
  if split and path then
    -- review diff buffers
    local current_review = reviews.get_current_review()
    if current_review and #current_review.threads > 0 then
      current_review.layout:get_current_file():place_signs()
    end
  elseif buffer then
    -- issue/pr/reviewthread buffers
    buffer:configure()
  end
end

function M.save_buffer()
  local buffer = utils.get_current_buffer()
  buffer:save()
end

---@class ReloadOpts
---@field bufnr number
---@field verbose? boolean

--- Load issue/pr/repo buffer
---@param opts? ReloadOpts
---@return nil
function M.load_buffer(opts)
  opts = opts or {}
  local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  local bufname = vim.fn.bufname(bufnr)
  local repo, kind, id = string.match(bufname, "octo://(.+)/(.+)/([0-9a-z.]+)")
  if not repo then
    repo = string.match(bufname, "octo://(.+)/repo")
    if repo then
      kind = "repo"
    end
  end
  if (kind == "issue" or kind == "pull") and not repo and not id then
    utils.print_err("Incorrect buffer: " .. bufname)
    return
  elseif kind == "repo" and not repo then
    utils.print_err("Incorrect buffer: " .. bufname)
    return
  end
  M.load(repo, kind, id, function(obj)
    vim.api.nvim_buf_call(bufnr, function()
      M.create_buffer(kind, obj, repo, false)

      -- get size of newly created buffer
      local lines = vim.api.nvim_buf_line_count(bufnr)

      -- One to the left
      local new_cursor_pos = {
        math.min(cursor_pos[1], lines),
        math.max(0, cursor_pos[2] - 1),
      }
      vim.api.nvim_win_set_cursor(0, new_cursor_pos)

      if opts.verbose then
        utils.info(string.format("Loaded %s/%s/%d", repo, kind, id))
      end
    end)
  end)
end

---@param repo string
---@param kind octo.NodeKind
---@param id integer|string pull request, issue, or discussion number or release tag
---@param cb fun(obj: octo.Issue|octo.PullRequest|octo.Discussion|octo.Release|octo.Repository): nil
function M.load(repo, kind, id, cb)
  local owner, name = utils.split_repo(repo)

  ---@type string, string, table<string, string|integer>
  local query, key, fields
  if kind == "pull" then
    query = graphql("pull_request_query", owner, name, id, _G.octo_pv2_fragment)
    key = "pullRequest"
    fields = {}
  elseif kind == "issue" then
    query = graphql("issue_query", owner, name, id, _G.octo_pv2_fragment)
    key = "issue"
    fields = {}
  elseif kind == "repo" then
    query = queries.repository
    fields = { owner = owner, name = name }
  elseif kind == "discussion" then
    query = queries.discussion
    fields = { owner = owner, name = name, number = id }
  elseif kind == "release" then
    query = queries.release
    fields = { owner = owner, name = name, tag = id }
  end

  local function load_buffer(output)
    if kind == "pull" or kind == "issue" then
      local resp = utils.aggregate_pages(output, string.format("data.repository.%s.timelineItems.nodes", key))
      ---@type octo.Issue|octo.PullRequest
      local obj = resp.data.repository[key]
      cb(obj)
    elseif kind == "repo" then
      local resp = vim.json.decode(output)
      ---@type octo.Repository
      local obj = resp.data.repository
      cb(obj)
    elseif kind == "discussion" then
      local resp = utils.aggregate_pages(output, "data.repository.discussion.comments.nodes")
      ---@type octo.Discussion
      local obj = resp.data.repository.discussion
      cb(obj)
    elseif kind == "release" then
      local resp = vim.json.decode(output)
      ---@type octo.Release
      local obj = resp.data.repository.release
      cb(obj)
    else
      utils.error("Unknown kind: " .. kind)
    end
  end

  gh.api.graphql {
    query = query,
    fields = fields,
    paginate = true,
    jq = ".",
    opts = {
      cb = gh.create_callback { failure = utils.print_err, success = load_buffer },
    },
  }
end

function M.render_signs()
  local buffer = utils.get_current_buffer()
  buffer:render_signs()
end

function M.on_cursor_hold()
  local buffer = utils.get_current_buffer()
  if not buffer then
    return
  end

  -- reactions popup
  local id = buffer:get_reactions_at_cursor()
  if id then
    local query = graphql("reactions_for_object_query", id)
    gh.run {
      args = { "api", "graphql", "-f", string.format("query=%s", query) },
      cb = function(output, stderr)
        if stderr and not utils.is_blank(stderr) then
          utils.print_err(stderr)
        elseif output then
          ---@type octo.queries.ReactionsForObject
          local resp = vim.json.decode(output)
          local reactions = {} ---@type table<string, string[]>
          local reactionGroups = resp.data.node.reactionGroups
          for _, reactionGroup in ipairs(reactionGroups) do
            local users = reactionGroup.users.nodes
            local logins = {} ---@type string[]
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
    return
  end

  -- user popup
  local login = utils.extract_pattern_at_cursor(constants.USER_PATTERN)
  if login then
    local query = graphql("user_profile_query", login)
    gh.run {
      args = { "api", "graphql", "-f", string.format("query=%s", query) },
      cb = function(output, stderr)
        if stderr and not utils.is_blank(stderr) then
          utils.print_err(stderr)
        elseif output then
          ---@type octo.queries.UserProfile
          local resp = vim.json.decode(output)
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
    return
  end

  -- link popup
  local repo, number = utils.extract_issue_at_cursor(buffer.repo)
  if not repo or not number then
    return
  end
  ---@generic TData
  ---@param data TData
  ---@param write_summary fun(bufnr: integer, data: TData, opts: { max_length: integer }): integer
  local function write_popup(data, write_summary)
    local popup_bufnr = vim.api.nvim_create_buf(false, true)
    local max_length = 80
    local lines = write_summary(popup_bufnr, data, { max_length = max_length })
    window.create_popup {
      bufnr = popup_bufnr,
      width = 80,
      height = 2 + lines,
    }
  end
  local owner, name = utils.split_repo(repo)
  local query = graphql("issue_summary_query", owner, name, number)
  gh.api.graphql {
    query = query,
    jq = ".data.repository.issueOrPullRequest",
    opts = {
      cb = gh.create_callback {
        success = function(output)
          ---@type octo.IssueOrPullRequestSummary
          local issue = vim.json.decode(output)
          write_popup(issue, writers.write_issue_summary)
        end,
        failure = function(_)
          gh.api.graphql {
            query = queries.discussion_summary,
            F = { owner = owner, name = name, number = number },
            jq = ".data.repository.discussion",
            opts = {
              cb = gh.create_callback {
                failure = utils.print_err,
                success = function(output)
                  ---@type octo.DiscussionSummary
                  local discussion = vim.json.decode(output)
                  write_popup(discussion, writers.write_discussion_summary)
                end,
              },
            },
          }
        end,
      },
    },
  }
end

---@param kind "repo"|"discussion"|"release"|"issue"|"pull_request"
---@param obj octo.Issue|octo.PullRequest|octo.Discussion|octo.Release|octo.Repository
---@param repo string
---@param create boolean
function M.create_buffer(kind, obj, repo, create)
  if not obj.id then
    utils.error("Cannot find " .. repo)
    return
  end

  local bufnr ---@type integer
  if create then
    bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.cmd(string.format("file octo://%s/%s/%d", repo, kind, obj.number))
  else
    bufnr = vim.api.nvim_get_current_buf()
  end

  local octo_buffer = OctoBuffer:new {
    bufnr = bufnr,
    number = obj.number,
    repo = repo,
    node = obj,
    kind = kind,
  }

  octo_buffer:configure()
  if kind == "repo" then
    octo_buffer:render_repo()
  elseif kind == "discussion" then
    octo_buffer:render_discussion()
  elseif kind == "release" then
    octo_buffer:render_release()
  else
    octo_buffer:render_issue()
    octo_buffer:async_fetch_taggable_users()
    octo_buffer:async_fetch_issues()
  end
end

return M
