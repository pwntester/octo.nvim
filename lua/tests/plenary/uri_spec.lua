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

    it("parses a repo with hostname", function()
      local uri_str = "octo://github.com/pwntester/octo.nvim/repo"
      local parsed = uri.parse(uri_str)

      eq({
        hostname = "github.com",
        repo = "pwntester/octo.nvim",
        kind = "repo",
        id = "repo",
      }, parsed)
    end)

    it("parses an issue with hostname", function()
      local uri_str = "octo://github.com/pwntester/octo.nvim/issue/42"
      local parsed = uri.parse(uri_str)

      eq({
        hostname = "github.com",
        repo = "pwntester/octo.nvim",
        kind = "issue",
        id = "42",
      }, parsed)
    end)

    it("parses a pull request with hostname", function()
      local uri_str = "octo://github.com/pwntester/octo.nvim/pull/42"
      local parsed = uri.parse(uri_str)

      eq({
        hostname = "github.com",
        repo = "pwntester/octo.nvim",
        kind = "pull",
        id = "42",
      }, parsed)
    end)

    it("parses a discussion with hostname", function()
      local uri_str = "octo://github.com/pwntester/octo.nvim/discussion/42"
      local parsed = uri.parse(uri_str)

      eq({
        hostname = "github.com",
        repo = "pwntester/octo.nvim",
        kind = "discussion",
        id = "42",
      }, parsed)
    end)

    it("parses a release with hostname", function()
      local uri_str = "octo://github.com/pwntester/octo.nvim/release/v1.0.0"
      local parsed = uri.parse(uri_str)

      eq({
        hostname = "github.com",
        repo = "pwntester/octo.nvim",
        kind = "release",
        id = "v1.0.0",
      }, parsed)
    end)

    it("parses GitHub Enterprise hostname", function()
      local uri_str = "octo://github.enterprise.com/myorg/myrepo/issue/123"
      local parsed = uri.parse(uri_str)

      eq({
        hostname = "github.enterprise.com",
        repo = "myorg/myrepo",
        kind = "issue",
        id = "123",
      }, parsed)
    end)

    it("normalizes plural issue to singular", function()
      local uri_str = "octo://pwntester/octo.nvim/issues/42"
      local parsed = uri.parse(uri_str)

      eq({
        repo = "pwntester/octo.nvim",
        kind = "issue",
        id = "42",
      }, parsed)
    end)

    it("normalizes plural pull to singular", function()
      local uri_str = "octo://pwntester/octo.nvim/pulls/42"
      local parsed = uri.parse(uri_str)

      eq({
        repo = "pwntester/octo.nvim",
        kind = "pull",
        id = "42",
      }, parsed)
    end)

    it("normalizes plural discussion to singular", function()
      local uri_str = "octo://pwntester/octo.nvim/discussions/42"
      local parsed = uri.parse(uri_str)

      eq({
        repo = "pwntester/octo.nvim",
        kind = "discussion",
        id = "42",
      }, parsed)
    end)

    it("normalizes plural with hostname", function()
      local uri_str = "octo://github.com/pwntester/octo.nvim/issues/42"
      local parsed = uri.parse(uri_str)

      eq({
        hostname = "github.com",
        repo = "pwntester/octo.nvim",
        kind = "issue",
        id = "42",
      }, parsed)
    end)
  end)
end)
