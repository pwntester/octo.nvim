---@diagnostic disable
local uri = require "octo.uri"
local eq = assert.are.same

describe("Uri module:", function()
  describe("uri.parse", function()
    it("parses a repo", function()
      local uri_str = "octo://pwntester/octo.nvim/repo"
      local parsed = uri.parse(uri_str)

      eq({
        repo = "pwntester/octo.nvim",
        kind = "repo",
        id = "repo",
      }, parsed)
    end)

    it("parses an issue", function()
      local uri_str = "octo://pwntester/octo.nvim/issue/42"
      local parsed = uri.parse(uri_str)

      eq({
        repo = "pwntester/octo.nvim",
        kind = "issue",
        id = "42",
      }, parsed)
    end)

    it("parses an pull request", function()
      local uri_str = "octo://pwntester/octo.nvim/pull/42"
      local parsed = uri.parse(uri_str)

      eq({
        repo = "pwntester/octo.nvim",
        kind = "pull",
        id = "42",
      }, parsed)
    end)

    it("parses a discussion", function()
      local uri_str = "octo://pwntester/octo.nvim/discussion/42"
      local parsed = uri.parse(uri_str)

      eq({
        repo = "pwntester/octo.nvim",
        kind = "discussion",
        id = "42",
      }, parsed)
    end)

    it("parses a release", function()
      local uri_str = "octo://pwntester/octo.nvim/release/abcd1234"
      local parsed = uri.parse(uri_str)

      eq({
        repo = "pwntester/octo.nvim",
        kind = "release",
        id = "abcd1234",
      }, parsed)
    end)
  end)
end)
