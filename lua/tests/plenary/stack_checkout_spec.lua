---@diagnostic disable
local eq = assert.are.same

describe("Octo stack checkout:", function()
  local stack
  local gh
  local utils
  local checkout_opts
  local info_messages
  local error_messages

  before_each(function()
    checkout_opts = nil
    info_messages = {}
    error_messages = {}

    stack = require "octo.stack"
    gh = require "octo.gh"
    utils = require "octo.utils"

    gh.stack = {
      checkout = function(opts)
        checkout_opts = opts
      end,
    }

    utils.get_current_buffer = function()
      return {
        number = 333,
        repo = "owner/repo",
        isPullRequest = function()
          return true
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
  end)

  after_each(function()
    package.loaded["octo.stack"] = nil
    package.loaded["octo.gh"] = nil
    package.loaded["octo.utils"] = nil
  end)

  it("checks out an explicit stack or PR number", function()
    stack.checkout(42)
    assert.is_not_nil(checkout_opts)
    eq(42, checkout_opts[1])
  end)

  it("defaults to the current PR buffer's number", function()
    stack.checkout()
    assert.is_not_nil(checkout_opts)
    eq(333, checkout_opts[1])
  end)

  it("errors without a number outside PR buffers", function()
    utils.get_current_buffer = function()
      return nil
    end
    stack.checkout()
    eq(nil, checkout_opts)
    eq(1, #error_messages)
  end)

  it("errors when the current checkout is a different repo", function()
    utils.get_remote_name = function()
      return "other/repo"
    end
    stack.checkout()
    eq(nil, checkout_opts)
    assert.is_truthy(error_messages[1]:find("owner/repo", 1, true))
  end)

  it("reports success with a fallback message", function()
    stack.checkout(42)
    checkout_opts.opts.cb("", "", 0)
    assert.is_truthy(info_messages[#info_messages]:find("Stack checked out", 1, true))
  end)

  it("suggests installing the gh-stack extension when the command is unknown", function()
    stack.checkout(42)
    checkout_opts.opts.cb("", 'unknown command "stack" for "gh"', 1)
    assert.is_truthy(error_messages[1]:find("gh extension install github/gh-stack", 1, true))
  end)

  it("passes other failures through", function()
    stack.checkout(42)
    checkout_opts.opts.cb("", "local stack has diverged", 1)
    assert.is_truthy(error_messages[1]:find("diverged", 1, true))
  end)
end)
