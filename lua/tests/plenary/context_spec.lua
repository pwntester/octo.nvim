---@diagnostic disable
local context = require "octo.context"
local utils = require "octo.utils"
local eq = assert.are.same

describe("context.within_pr:", function()
  local original_get_current_buffer = utils.get_current_buffer
  local original_error = utils.error
  local error_messages

  local function fake_pr_buffer()
    return {
      isPullRequest = function()
        return true
      end,
    }
  end

  before_each(function()
    error_messages = {}
    utils.error = function(msg)
      table.insert(error_messages, msg)
    end
  end)

  after_each(function()
    utils.get_current_buffer = original_get_current_buffer
    utils.error = original_error
  end)

  it("forwards extra arguments to the callback", function()
    utils.get_current_buffer = fake_pr_buffer

    local received
    local action = context.within_pr(function(_buffer, ...)
      received = { ... }
    end)

    action("base", "extra")

    eq({ "base", "extra" }, received)
  end)

  it("still passes the buffer as the first argument", function()
    local buffer = fake_pr_buffer()
    utils.get_current_buffer = function()
      return buffer
    end

    local received
    local action = context.within_pr(function(b)
      received = b
    end)

    action()

    eq(buffer, received)
  end)

  it("errors without calling the callback outside a PR buffer", function()
    utils.get_current_buffer = function()
      return nil
    end

    local called = false
    local action = context.within_pr(function()
      called = true
    end)

    action "base"

    eq(false, called)
    eq({ "Not a Pull Request buffer" }, error_messages)
  end)

  it("errors without calling the callback for a non-PR buffer", function()
    utils.get_current_buffer = function()
      return {
        isPullRequest = function()
          return false
        end,
      }
    end

    local called = false
    local action = context.within_pr(function()
      called = true
    end)

    action "base"

    eq(false, called)
    eq({ "Not a Pull Request buffer" }, error_messages)
  end)
end)
