---@diagnostic disable
local eq = assert.are.same

describe("save_pr base branch selection:", function()
  local commands
  local utils
  local picker
  local config

  local picker_calls
  local error_messages
  local repo_infos
  local orig

  local FORK = "viewer/octo.nvim"
  local UPSTREAM = "pwntester/octo.nvim"

  local function make_info(name_with_owner, default_branch, branches, parent)
    local nodes = {}
    for _, branch in ipairs(branches) do
      table.insert(nodes, { name = branch })
    end
    return {
      nameWithOwner = name_with_owner,
      isFork = parent ~= nil,
      parent = parent and { nameWithOwner = parent } or nil,
      defaultBranchRef = { name = default_branch },
      refs = { nodes = nodes },
    }
  end

  local function save_pr_opts(overrides)
    local opts = {
      repo = FORK,
      base_title = "",
      base_body = "",
      candidates = { FORK, UPSTREAM },
      candidate_entries = { "Select target repo", "1. " .. FORK, "2. " .. UPSTREAM },
      is_draft = false,
      info = repo_infos[FORK],
      remote_branch = "feature",
    }
    return vim.tbl_extend("force", opts, overrides or {})
  end

  before_each(function()
    commands = require "octo.commands"
    utils = require "octo.utils"
    picker = require "octo.picker"
    config = require "octo.config"
    config.setup {}
    vim.g.octo_viewer = "viewer"

    picker_calls = {}
    error_messages = {}
    repo_infos = {
      [FORK] = make_info(FORK, "fork-default", { "fork-default", "feature" }, UPSTREAM),
      [UPSTREAM] = make_info(UPSTREAM, "master", { "master", "release-1.x" }),
    }

    orig = {
      get_repo_info = utils.get_repo_info,
      get_repo_id = utils.get_repo_id,
      error = utils.error,
      branches = rawget(picker, "branches"),
      input = vim.fn.input,
      inputlist = vim.fn.inputlist,
      confirm = vim.fn.confirm,
    }

    utils.get_repo_info = function(repo)
      return repo_infos[repo]
    end
    utils.get_repo_id = function()
      return "repo-id"
    end
    utils.error = function(msg)
      table.insert(error_messages, msg)
    end

    -- Record picker invocations and always pick the first offered branch
    picker.branches = function(opts, cb)
      table.insert(picker_calls, opts)
      local first = opts.repo.refs.nodes[1]
      cb(first and first.name or nil)
    end

    vim.fn.input = function()
      return "PR title"
    end
    -- 2 = second target repo candidate (the fork's parent)
    vim.fn.inputlist = function()
      return 2
    end
    -- 2 = "No", aborts before the createPullRequest mutation
    vim.fn.confirm = function()
      return 2
    end
  end)

  after_each(function()
    utils.get_repo_info = orig.get_repo_info
    utils.get_repo_id = orig.get_repo_id
    utils.error = orig.error
    picker.branches = orig.branches
    vim.fn.input = orig.input
    vim.fn.inputlist = orig.inputlist
    vim.fn.confirm = orig.confirm
  end)

  it("offers BASE branches of the selected target repo, not of the source repo", function()
    commands.save_pr(save_pr_opts())

    eq(2, #picker_calls)
    local base = picker_calls[1]
    eq("Select BASE branch", base.title)
    eq({ { name = "master" }, { name = "release-1.x" } }, base.repo.refs.nodes)
  end)

  it("marks the target repo default branch as default in the BASE picker", function()
    commands.save_pr(save_pr_opts())

    eq("master", picker_calls[1].default_branch_name)
  end)

  it("offers HEAD branches of the source repo", function()
    commands.save_pr(save_pr_opts())

    local head = picker_calls[2]
    eq("Select HEAD branch", head.title)
    eq({ { name = "fork-default" }, { name = "feature" } }, head.repo.refs.nodes)
  end)

  it("keeps using the source repo when the target repo is the source repo", function()
    vim.fn.inputlist = function()
      return 1
    end

    commands.save_pr(save_pr_opts())

    eq({ { name = "fork-default" }, { name = "feature" } }, picker_calls[1].repo.refs.nodes)
    eq("fork-default", picker_calls[1].default_branch_name)
  end)

  it("aborts when no target repo is picked", function()
    vim.fn.inputlist = function()
      return 0
    end

    commands.save_pr(save_pr_opts())

    eq(0, #picker_calls)
    eq(1, #error_messages)
  end)

  it("aborts when the target repo info cannot be fetched", function()
    repo_infos[UPSTREAM] = nil

    commands.save_pr(save_pr_opts())

    eq(0, #picker_calls)
    eq(1, #error_messages)
  end)
end)
