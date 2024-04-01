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
local signs = require "octo.ui.signs"
local utils = require "octo.utils"
local vim = vim

_G.octo_repo_issues = {}
_G.octo_buffers = {}
_G.octo_colors_loaded = false

local M = {}

function M.setup(user_config)
  if not vim.fn.has "nvim-0.7" then
    utils.error "octo.nvim requires neovim 0.7+"
    return
  end

  config.setup(user_config or {})
  if not backend.available_executable() then
    return
  end

  signs.setup()
  picker.setup()
  completion.setup()
  folds.setup()
  autocmds.setup()
  commands.setup()
  local func = backend.get_funcs()["setup"]
  func()
end

function M.configure_octo_buffer(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local split, path = utils.get_split_and_path(bufnr)
  local buffer = octo_buffers[bufnr]
  if split and path then
    -- review diff buffers
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
    vim.api.nvim_buf_call(bufnr, function()
      M.create_buffer(kind, obj, repo, false)
    end)
  end)
end

function M.load(repo, kind, number, cb)
  local func = backend.get_funcs()["load"]
  func(repo, kind, number, cb)
end

function M.render_signs()
  local bufnr = vim.api.nvim_get_current_buf()
  local buffer = octo_buffers[bufnr]
  buffer:render_signs()
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
    local func = backend.get_funcs()["reactions_popup"]
    func(id)
    return
  end

  -- user popup
  local login = utils.extract_pattern_at_cursor(constants.USER_PATTERN)
  if login then
    local func = backend.get_funcs()["user_popup"]
    func(login)
    return
  end

  -- link popup
  local repo, number = utils.extract_issue_at_cursor(buffer.repo)
  if not repo or not number then
    return
  end
  local func = backend.get_funcs()["link_popup"]
  func(repo, number)
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
