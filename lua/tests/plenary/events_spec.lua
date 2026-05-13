---@diagnostic disable
local events = require "octo.events"
local eq = assert.are.same

describe("Events module:", function()
  describe("constants", function()
    it("define review lifecycle events.", function()
      eq(events.REVIEW_OPENED, "OctoReviewOpened")
      eq(events.REVIEW_CLOSED, "OctoReviewClosed")
      eq(events.REVIEW_SUBMITTED, "OctoReviewSubmitted")
      eq(events.REVIEW_DISCARDED, "OctoReviewDiscarded")
    end)

    it("define buffer lifecycle events.", function()
      eq(events.BUFFER_LOADED, "OctoBufferLoaded")
      eq(events.BUFFER_CLOSED, "OctoBufferClosed")
    end)

    it("define comment lifecycle events.", function()
      eq(events.COMMENT_ADDED, "OctoCommentAdded")
      eq(events.COMMENT_UPDATED, "OctoCommentUpdated")
      eq(events.COMMENT_DELETED, "OctoCommentDeleted")
    end)
  end)

  describe("emit", function()
    it("fires a User autocommand with the given pattern and data.", function()
      local received = false
      vim.api.nvim_create_autocmd("User", {
        pattern = events.COMMENT_ADDED,
        once = true,
        callback = function(opts)
          received = true
          eq(opts.data.comment_id, "123")
          eq(opts.data.body, "test body")
        end,
      })

      events.emit(events.COMMENT_ADDED, {
        comment_id = "123",
        body = "test body",
        kind = "IssueComment",
      })

      vim.wait(50, function()
        return false
      end)
      assert.is_true(received)
    end)

    it("delivers data through vim.v.event.", function()
      local result
      vim.api.nvim_create_autocmd("User", {
        pattern = events.REVIEW_SUBMITTED,
        once = true,
        callback = function(opts)
          result = opts.data
        end,
      })

      events.emit(events.REVIEW_SUBMITTED, {
        review_id = "42",
        action = "APPROVE",
      })

      vim.wait(50, function()
        return false
      end)
      eq(result.review_id, "42")
      eq(result.action, "APPROVE")
    end)
  end)
end)
