---@diagnostic disable
local eq = assert.are.same

describe("merge_pr_stack:", function()
  local commands
  local gh
  local utils
  local config
  local captured_opts
  local confirm_questions
  local confirm_answer
  local info_messages
  local error_messages

  -- Minimal fake PR buffer for a PR that sits at position 2 of a 3-PR stack
  local function make_stack_entry()
    return {
      position = 2,
      stack = {
        id = "S_1",
        number = 350,
        size = 3,
        baseRefName = "main",
        entries = {
          nodes = {
            {
              position = 3,
              pullRequest = { number = 343, title = "Top PR", state = "OPEN", isDraft = false, url = "" },
            },
            {
              position = 1,
              pullRequest = { number = 330, title = "Bottom PR", state = "OPEN", isDraft = false, url = "" },
            },
            {
              position = 2,
              pullRequest = { number = 333, title = "Current PR", state = "OPEN", isDraft = false, url = "" },
            },
          },
        },
      },
    }
  end

  local function make_pr_buffer(pr_number, repo, stack_entry)
    return {
      number = pr_number,
      repo = repo,
      isPullRequest = function()
        return true
      end,
      pullRequest = function()
        return {
          baseRepository = { nameWithOwner = repo },
          stackEntry = stack_entry,
        }
      end,
      bufnr = 1,
    }
  end

  local stack_entry

  before_each(function()
    captured_opts = nil
    confirm_questions = {}
    confirm_answer = true
    info_messages = {}
    error_messages = {}
    stack_entry = make_stack_entry()

    -- Normally defined when octo/init.lua loads; ensure it exists when this
    -- spec runs standalone so writers.write_state can early-return
    _G.octo_buffers = _G.octo_buffers or {}

    commands = require "octo.commands"
    gh = require "octo.gh"
    utils = require "octo.utils"
    config = require "octo.config"

    config.setup { default_merge_method = "merge" }

    utils.get_current_buffer = function()
      return make_pr_buffer(333, "owner/repo", stack_entry)
    end

    utils.get_remote_name = function()
      return "owner/repo"
    end

    utils.confirm = function(question)
      table.insert(confirm_questions, question)
      return confirm_answer
    end

    utils.info = function(msg)
      table.insert(info_messages, msg)
    end

    utils.error = function(msg)
      table.insert(error_messages, msg)
    end

    -- Shadow the dynamic gh.stack subcommand to capture opts instead of running gh
    gh.stack = {
      merge = function(opts)
        captured_opts = opts
      end,
    }
  end)

  after_each(function()
    package.loaded["octo.gh"] = nil
    package.loaded["octo.commands"] = nil
    package.loaded["octo.utils"] = nil
  end)

  it("merge_pr('stack') calls gh stack merge with the PR number, --yes and default method", function()
    commands.merge_pr "stack"

    assert.is_not_nil(captured_opts)
    eq(333, captured_opts[1])
    eq(true, captured_opts.yes)
    eq(true, captured_opts.merge)
    eq(nil, captured_opts.squash)
    eq(nil, captured_opts.rebase)
  end)

  it("merge_pr('stack', 'squash') uses the squash method", function()
    commands.merge_pr("stack", "squash")

    assert.is_not_nil(captured_opts)
    eq(true, captured_opts.squash)
    eq(nil, captured_opts.merge)
  end)

  it("errors when the PR is not part of a stack", function()
    stack_entry = nil
    commands.merge_pr "stack"

    eq(nil, captured_opts)
    eq(1, #error_messages)
    assert.is_truthy(error_messages[1]:find("not part of a stack", 1, true))
  end)

  it("errors when the current checkout is a different repo", function()
    utils.get_remote_name = function()
      return "other/repo"
    end
    commands.merge_pr "stack"

    eq(nil, captured_opts)
    eq(1, #error_messages)
    assert.is_truthy(error_messages[1]:find("owner/repo", 1, true))
  end)

  it("does not merge when the confirmation is declined", function()
    confirm_answer = false
    commands.merge_pr "stack"

    eq(nil, captured_opts)
    eq(1, #confirm_questions)
  end)

  it("confirmation lists only the PRs at or below the current position", function()
    commands.merge_pr "stack"

    eq(1, #confirm_questions)
    local question = confirm_questions[1]
    assert.is_truthy(question:find("#330", 1, true))
    assert.is_truthy(question:find("#333", 1, true))
    assert.is_nil(question:find("#343", 1, true))
    assert.is_truthy(question:find("main", 1, true))
  end)

  it("confirmation skips PRs in the stack that are already merged", function()
    stack_entry.stack.entries.nodes[2].pullRequest.state = "MERGED"
    commands.merge_pr "stack"

    eq(1, #confirm_questions)
    local question = confirm_questions[1]
    assert.is_nil(question:find("#330", 1, true))
    assert.is_truthy(question:find("Merge 1 pull request(s) (#333)", 1, true))
  end)

  it("reports success with a fallback message when gh output is blank", function()
    commands.merge_pr "stack"

    assert.is_not_nil(captured_opts)
    captured_opts.opts.cb("", "", 0)
    eq(1, #info_messages)
    eq("Stack merged successfully", info_messages[1])
  end)

  it("suggests installing the gh-stack extension when the command is unknown", function()
    commands.merge_pr "stack"

    assert.is_not_nil(captured_opts)
    captured_opts.opts.cb("", 'unknown command "stack" for "gh"', 1)
    eq(1, #error_messages)
    assert.is_truthy(error_messages[1]:find("gh extension install github/gh-stack", 1, true))
  end)
end)
