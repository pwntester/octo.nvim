---@diagnostic disable
local eq = assert.are.same

describe("Octo stack create:", function()
  local stack
  local gh
  local utils
  local view_opts
  local submit_opts
  local pr_list_opts
  local previewed
  local info_messages
  local error_messages

  local function make_stack_data()
    return {
      trunk = "master",
      currentBranch = "feat-b",
      branches = {
        {
          name = "feat-a",
          isCurrent = false,
          isMerged = false,
          isQueued = false,
          needsRebase = false,
          pr = { number = 1, url = "", state = "OPEN" },
        },
        {
          name = "feat-b",
          isCurrent = true,
          isMerged = false,
          isQueued = false,
          needsRebase = false,
        },
      },
    }
  end

  before_each(function()
    view_opts = nil
    submit_opts = nil
    pr_list_opts = nil
    previewed = nil
    info_messages = {}
    error_messages = {}

    stack = require "octo.stack"
    gh = require "octo.gh"
    utils = require "octo.utils"

    gh.stack = {
      view = function(opts)
        view_opts = opts
      end,
      submit = function(opts)
        submit_opts = opts
      end,
    }
    gh.pr = {
      list = function(opts)
        pr_list_opts = opts
      end,
    }

    utils.get_current_buffer = function()
      return {
        number = 333,
        repo = "owner/repo",
        isPullRequest = function()
          return true
        end,
        pullRequest = function()
          return { headRefName = "feat-b" }
        end,
      }
    end
    utils.get_remote_name = function()
      return "owner/repo"
    end

    utils.info = function(msg)
      table.insert(info_messages, msg)
    end
    utils.error = function(msg)
      table.insert(error_messages, msg)
    end

    stack.show_stack_preview = function(s, on_confirm)
      previewed = { stack = s, on_confirm = on_confirm }
    end
  end)

  after_each(function()
    package.loaded["octo.stack"] = nil
    package.loaded["octo.gh"] = nil
    package.loaded["octo.utils"] = nil
  end)

  describe("build_stack_preview", function()
    it("lists branches top of the stack first with the trunk last", function()
      local lines = stack.build_stack_preview(make_stack_data())
      assert.is_truthy(lines[1]:find("feat-b", 1, true))
      assert.is_truthy(lines[2]:find("feat-a", 1, true))
      assert.is_truthy(lines[3]:find("master", 1, true))
    end)

    it("marks the current branch and annotates the PR state", function()
      local lines = stack.build_stack_preview(make_stack_data())
      assert.is_truthy(lines[1]:find("▶", 1, true))
      assert.is_truthy(lines[1]:find("new PR", 1, true))
      assert.is_nil(lines[2]:find("▶", 1, true))
      assert.is_truthy(lines[2]:find("#1 (OPEN)", 1, true))
    end)

    it("warns only when a branch needs a rebase", function()
      local lines = stack.build_stack_preview(make_stack_data())
      assert.is_nil(table.concat(lines, "\n"):find("rebase", 1, true))

      local stack_data = make_stack_data()
      stack_data.branches[1].needsRebase = true
      lines = stack.build_stack_preview(stack_data)
      assert.is_truthy(table.concat(lines, "\n"):find("rebase", 1, true))
    end)
  end)

  describe("create", function()
    it("requests the stack as JSON", function()
      stack.create()
      assert.is_not_nil(view_opts)
      eq(true, view_opts.json)
    end)

    it("lists enough PRs to reach older anchors", function()
      stack.create()
      view_opts.opts.cb("", "not in a stack", 2)
      eq("1000", pr_list_opts.limit)
    end)

    it("seeds the anchor PR from the buffer when the listing misses it", function()
      utils.get_current_buffer = function()
        return {
          number = 101,
          repo = "owner/repo",
          isPullRequest = function()
            return true
          end,
          pullRequest = function()
            return {
              title = "Parent feature",
              state = "OPEN",
              headRefName = "feat-parent",
              baseRefName = "master",
            }
          end,
        }
      end
      stack.create()
      view_opts.opts.cb("", "not in a stack", 2)
      -- the listing window does not include the (older) anchor PR itself,
      -- only its dependent
      local listed = {
        {
          number = 102,
          title = "Dependent feature",
          state = "OPEN",
          headRefName = "feat-child",
          baseRefName = "feat-parent",
        },
      }
      pr_list_opts.opts.cb(vim.json.encode(listed), "", 0)

      assert.is_not_nil(previewed)
      eq("master", previewed.stack.trunk)
      eq(2, #previewed.stack.branches)
      eq("feat-parent", previewed.stack.branches[1].name)
      eq(true, previewed.stack.branches[1].isCurrent)
      eq("feat-child", previewed.stack.branches[2].name)
    end)

    it("anchors on the PR buffer when it is not part of the local stack", function()
      utils.get_current_buffer = function()
        return {
          number = 102,
          repo = "owner/repo",
          isPullRequest = function()
            return true
          end,
          pullRequest = function()
            return { headRefName = "feat-parent" }
          end,
        }
      end
      stack.create()
      view_opts.opts.cb(vim.json.encode(make_stack_data()), "", 0)
      -- the locally tracked stack does not contain the buffer's branch:
      -- discovery around the buffer's PR takes over instead
      eq(nil, previewed)
      assert.is_not_nil(pr_list_opts)
    end)

    it("falls back to PR discovery when not in a stack", function()
      stack.create()
      view_opts.opts.cb("", "current branch is not in a stack", 2)
      eq(nil, previewed)
      eq(0, #error_messages)
      -- discovery path (covered in stack_discover_spec) takes over
      assert.is_not_nil(pr_list_opts)
    end)

    it("suggests installing the gh-stack extension when the command is unknown", function()
      stack.create()
      view_opts.opts.cb("", 'unknown command "stack" for "gh"', 1)
      eq(nil, previewed)
      assert.is_truthy(error_messages[1]:find("gh extension install github/gh-stack", 1, true))
    end)

    it("previews the decoded stack and submits on confirm", function()
      stack.create()
      view_opts.opts.cb(vim.json.encode(make_stack_data()), "", 0)

      assert.is_not_nil(previewed)
      eq("master", previewed.stack.trunk)
      eq(2, #previewed.stack.branches)
      eq(nil, submit_opts)

      previewed.on_confirm()
      assert.is_not_nil(submit_opts)
      eq(true, submit_opts.auto)
    end)
  end)

  describe("submit", function()
    it("reports success with a fallback message", function()
      stack.submit()
      submit_opts.opts.cb("", "", 0)
      assert.is_truthy(info_messages[#info_messages]:find("Stack submitted", 1, true))
    end)

    it("reports failures", function()
      stack.submit()
      submit_opts.opts.cb("", "push rejected", 1)
      eq(1, #error_messages)
      assert.is_truthy(error_messages[1]:find("push rejected", 1, true))
    end)
  end)
end)
