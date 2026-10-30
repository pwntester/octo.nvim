---@diagnostic disable
local config = require "octo.config"
local fragments = require "octo.gh.fragments"
local queries = require "octo.gh.queries"

config.setup {}
fragments.setup()
queries.setup()

local eq = assert.are.same

describe("remote branch lookup:", function()
  local gh = require "octo.gh"
  local utils = require "octo.utils"

  local original_graphql
  local captured

  local function stub_graphql(output)
    gh.api.graphql = function(opts)
      captured = opts
      return output
    end
  end

  before_each(function()
    captured = nil
    original_graphql = gh.api.graphql
  end)

  after_each(function()
    gh.api.graphql = original_graphql
  end)

  it("reports a branch that resolves on the remote", function()
    stub_graphql "feature-branch\n"
    assert.is_true(utils.remote_branch_exists("owner/repo", "feature-branch"))
  end)

  it("reports a branch that does not resolve", function()
    stub_graphql ""
    assert.is_false(utils.remote_branch_exists("owner/repo", "missing-branch"))
  end)

  it("reports a branch when the remote answers with a different ref", function()
    stub_graphql "other-branch"
    assert.is_false(utils.remote_branch_exists("owner/repo", "feature-branch"))
  end)

  it("asks for the single qualified ref rather than a page of branches", function()
    stub_graphql "feature-branch"
    utils.remote_branch_exists("owner/repo", "feature-branch")
    eq(queries.ref, captured.query)
    eq("owner", captured.fields.owner)
    eq("repo", captured.fields.name)
    eq("refs/heads/feature-branch", captured.fields.qualifiedName)
  end)

  it("skips the request when the repo or branch is blank", function()
    stub_graphql "feature-branch"
    assert.is_false(utils.remote_branch_exists("owner/repo", ""))
    assert.is_false(utils.remote_branch_exists("owner", "feature-branch"))
    assert.is_nil(captured)
  end)

  it("no longer pages branches in the repository query", function()
    assert.is_nil(queries.repository:find("refs(last:", 1, true))
  end)
end)
