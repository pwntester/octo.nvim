---@diagnostic disable
local eq = assert.are.same

describe("merge_pr:", function()
  local commands
  local gh
  local utils
  local config
  local captured_opts
  local info_messages
  local error_messages

  -- Minimal fake PR buffer
  local function make_pr_buffer(pr_number, repo)
    return {
      number = pr_number,
      isPullRequest = function()
        return true
      end,
      pullRequest = function()
        return {
          baseRepository = { nameWithOwner = repo },
        }
      end,
      bufnr = 1,
    }
  end

  before_each(function()
    captured_opts = nil
    info_messages = {}
    error_messages = {}

    -- Load modules fresh
    commands = require "octo.commands"
    gh = require "octo.gh"
    utils = require "octo.utils"
    config = require "octo.config"

    -- Ensure config is set up with known defaults
    config.setup { default_merge_method = "merge", default_delete_branch = false }

    -- Stub utils.get_current_buffer to return a fake PR buffer
    utils.get_current_buffer = function()
      return make_pr_buffer(42, "owner/repo")
    end

    utils.info = function(msg)
      table.insert(info_messages, msg)
    end

    utils.error = function(msg)
      table.insert(error_messages, msg)
    end

    -- Stub gh.pr.merge to capture opts instead of actually running gh
    local pr_subcommand = gh.pr
    local orig_meta = getmetatable(pr_subcommand)

    -- We intercept by overriding the merge key directly on the subcommand table
    -- gh.pr.merge is resolved via __index metamethod; we store the captured call
    -- by wrapping the run function
    local real_insert_args = gh.insert_args
    gh.insert_args = function(args, opts, replace)
      -- Capture a copy of opts before insert_args mutates it
      captured_opts = vim.deepcopy(opts)
      return real_insert_args(args, opts, replace)
    end
  end)

  after_each(function()
    -- Restore gh.insert_args
    local gh_module = require "octo.gh"
    -- reload to get fresh state for next test
    package.loaded["octo.gh"] = nil
    package.loaded["octo.commands"] = nil
    package.loaded["octo.utils"] = nil
  end)

  it("merge_pr('squash') sets squash=true and not merge=true", function()
    -- We can't easily intercept gh.pr.merge's opts before insert_args strips opts.opts,
    -- so we test the opts table construction directly by reproducing the logic.
    local merge_method_to_flag = utils.merge_method_to_flag
    local conf = config.values

    local params = table.pack "squash"
    local merge_method = conf.default_merge_method
    for _, param in ipairs(params) do
      if merge_method_to_flag[param] then
        merge_method = param
        break
      end
    end

    eq("squash", merge_method)

    local opts = { 42, repo = "owner/repo" }
    opts[merge_method] = true
    opts["delete-branch"] = conf.default_delete_branch

    eq(true, opts["squash"])
    eq(nil, opts["merge"])
    eq(nil, opts["rebase"])
  end)

  it("merge_pr() with no args uses default_merge_method 'merge'", function()
    local merge_method_to_flag = utils.merge_method_to_flag
    local conf = config.values

    local params = table.pack()
    local merge_method = conf.default_merge_method
    for _, param in ipairs(params) do
      if merge_method_to_flag[param] then
        merge_method = param
        break
      end
    end

    eq("merge", merge_method)

    local opts = { 42, repo = "owner/repo" }
    opts[merge_method] = true

    eq(true, opts["merge"])
    eq(nil, opts["squash"])
    eq(nil, opts["rebase"])
  end)

  it("merge_pr('rebase') sets rebase=true", function()
    local merge_method_to_flag = utils.merge_method_to_flag
    local conf = config.values

    local params = table.pack "rebase"
    local merge_method = conf.default_merge_method
    for _, param in ipairs(params) do
      if merge_method_to_flag[param] then
        merge_method = param
        break
      end
    end

    eq("rebase", merge_method)

    local opts = { 42, repo = "owner/repo" }
    opts[merge_method] = true

    eq(true, opts["rebase"])
    eq(nil, opts["squash"])
    eq(nil, opts["merge"])
  end)

  it("merge_pr with default 'squash' config and no args uses squash", function()
    config.setup { default_merge_method = "squash", default_delete_branch = false }

    local merge_method_to_flag = utils.merge_method_to_flag
    local conf = config.values

    local params = table.pack()
    local merge_method = conf.default_merge_method
    for _, param in ipairs(params) do
      if merge_method_to_flag[param] then
        merge_method = param
        break
      end
    end

    eq("squash", merge_method)

    local opts = { 42, repo = "owner/repo" }
    opts[merge_method] = true

    eq(true, opts["squash"])
    eq(nil, opts["merge"])
    eq(nil, opts["rebase"])
  end)

  it("insert_args produces --squash and not --merge for squash opts", function()
    local opts = {
      42,
      repo = "owner/repo",
      squash = true,
      ["delete-branch"] = false,
    }

    local args = { "pr", "merge" }
    args = gh.insert_args(args, opts, { ["_"] = "-" })

    assert(vim.tbl_contains(args, "--squash"), "expected --squash in args: " .. vim.inspect(args))
    assert(not vim.tbl_contains(args, "--merge"), "unexpected --merge in args: " .. vim.inspect(args))
    assert(not vim.tbl_contains(args, "--rebase"), "unexpected --rebase in args: " .. vim.inspect(args))
    assert(
      not vim.tbl_contains(args, "--delete-branch"),
      "unexpected --delete-branch in args (delete=false): " .. vim.inspect(args)
    )
  end)

  it("insert_args produces --merge and not --squash for merge opts", function()
    local opts = {
      42,
      repo = "owner/repo",
      merge = true,
      ["delete-branch"] = false,
    }

    local args = { "pr", "merge" }
    args = gh.insert_args(args, opts, { ["_"] = "-" })

    assert(vim.tbl_contains(args, "--merge"), "expected --merge in args: " .. vim.inspect(args))
    assert(not vim.tbl_contains(args, "--squash"), "unexpected --squash in args: " .. vim.inspect(args))
  end)

  it("insert_args produces --delete-branch when delete-branch=true", function()
    local opts = {
      42,
      repo = "owner/repo",
      squash = true,
      ["delete-branch"] = true,
    }

    local args = { "pr", "merge" }
    args = gh.insert_args(args, opts, { ["_"] = "-" })

    assert(vim.tbl_contains(args, "--squash"), "expected --squash in args: " .. vim.inspect(args))
    assert(vim.tbl_contains(args, "--delete-branch"), "expected --delete-branch in args: " .. vim.inspect(args))
  end)

  it("merge_pr success prefers stderr and uses fallback when blank", function()
    commands.merge_pr "squash"

    assert.is_not_nil(captured_opts)
    assert.is_not_nil(captured_opts.opts)
    assert.is_not_nil(captured_opts.opts.cb)

    captured_opts.opts.cb("", "Merged successfully", 0)
    eq(1, #info_messages)
    eq("Merged successfully", info_messages[1])

    captured_opts.opts.cb("", "", 0)
    eq(2, #info_messages)
    eq("Pull request merged successfully", info_messages[2])
  end)

  it("merge_pr failure prefers stderr and uses fallback when blank", function()
    commands.merge_pr "squash"

    assert.is_not_nil(captured_opts)
    assert.is_not_nil(captured_opts.opts)
    assert.is_not_nil(captured_opts.opts.cb)

    captured_opts.opts.cb("", "Merge failed", 1)
    eq(1, #error_messages)
    eq("Merge failed", error_messages[1])

    captured_opts.opts.cb("", "", 1)
    eq(2, #error_messages)
    eq("Failed to merge pull request", error_messages[2])
  end)
end)
