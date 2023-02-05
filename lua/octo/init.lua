local OctoBuffer = require("octo.model.octo-buffer").OctoBuffer
local autocmds = require "octo.autocmds"
local config = require "octo.config"
local constants = require "octo.constants"
local commands = require "octo.commands"
local completion = require "octo.completion"
local folds = require "octo.folds"
local backend = require "octo.backend"
local picker = require "octo.picker"
local reviews = require "octo.reviews"
local colors = require "octo.ui.colors"
local signs = require "octo.ui.signs"
local utils = require "octo.utils"

_G.octo_repo_issues = {}
_G.octo_buffers = {}

local M = {}

function M.setup(user_config)
  if backend.available_executables() == 0 then
    utils.error "gh and glab executable cli not found"
    return
  end
  if not vim.fn.has "nvim-0.7" then
    utils.error "octo.nvim requires neovim 0.7+"
    return
  end
  config.setup(user_config or {})
  signs.setup()
  picker.setup()
  colors.setup()
  completion.setup()
  folds.setup()
  autocmds.setup()
  commands.setup()
end

function M.configure_octo_buffer(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local split, path = utils.get_split_and_path(bufnr)
  local buffer = octo_buffers[bufnr]
  if split and path then
    -- review diff buffer
    local current_review = reviews.get_current_review()
    if current_review and #current_review.threads > 0 then
      current_review.layout:cur_file():place_signs()
    end
  elseif buffer then
    -- issue/pr/reviewthread buffers
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
  local repo, kind, number = string.match(bufname, "octo://(.+)/(.+)/(%d+)")
  if not repo then
    repo = string.match(bufname, "octo://(.+)/repo")
    if repo then
      kind = "repo"
    end
  end
  if (kind == "issue" or kind == "pull") and not repo and not number then
    vim.api.nvim_err_writeln("Incorrect buffer: " .. bufname)
    return
  elseif kind == "repo" and not repo then
    vim.api.nvim_err_writeln("Incorrect buffer: " .. bufname)
    return
  end
  M.load(repo, kind, number, function(obj)
    M.create_buffer(kind, obj, repo, false)
  end)
end

function M.load(repo, kind, number, cb)
  local opts = { repo=repo, number=number }
  backend.run(kind, opts, cb)
  -- cb(query_result)
end

function M.render_signcolumn()
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  buffer:render_signcolumn()
end

function M.on_cursor_hold()
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  if not buffer then
    return
  end

  -- reactions popup
  local id = buffer:get_reactions_at_cursor()
  if id then
    backend.run("reactions_popup", { id = id })
    return
  end

  -- user popup
  local login = utils.extract_pattern_at_cursor(constants.USER_PATTERN)
  if login then
    backend.run("user_popup", { login = login })
    return
  end

  -- link popup
  local repo, number = utils.extract_pattern_at_cursor(constants.LONG_ISSUE_PATTERN)
  if not repo or not number then
    repo = buffer.repo
    number = utils.extract_pattern_at_cursor(constants.SHORT_ISSUE_PATTERN)
  end
  if not repo or not number then
    repo, _, number = utils.extract_pattern_at_cursor(constants.URL_ISSUE_PATTERN)
  end
  if not repo or not number then
    return
  end

  backend.run("link_popup", { repo=repo, number=number })
end

function M.create_buffer(kind, obj, repo, create)
  if not obj.id then
    utils.error("Cannot find " .. repo)
    return
  end

  local bufnr
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
  }

  octo_buffer:configure()
  if kind == "repo" then
    octo_buffer:render_repo()
  else
    octo_buffer:render_issue()
    octo_buffer:async_fetch_taggable_users()
    octo_buffer:async_fetch_issues()
  end
end

return M
