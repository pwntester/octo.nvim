---@diagnostic disable
local eq = assert.are.same

describe("stack sync on GitHub:", function()
  local stack
  local utils
  local gh
  local queries
  local mutations
  local rebased ---@type table[] mutation calls, in order
  local info_messages
  local error_messages
  local confirm_answer
  local confirm_prompts
  local original_confirm
  local original_system
  local git_calls
  local heads ---@type table<integer, string> pull request number -> head oid
  local chain
  local behind ---@type table<string, integer> parent branch -> commits the child lacks
  local stub_kind ---@type fun(opts: table): string

  ---@param number integer
  ---@param opts table
  local function entry(number, position, opts)
    opts = opts or {}
    return {
      position = position,
      pullRequest = {
        id = "PR_" .. number,
        number = number,
        title = "part " .. position,
        state = opts.state or "OPEN",
        baseRefName = opts.base or "master",
        headRefName = opts.head or ("feature_" .. position),
        headRefOid = opts.oid or ("oid" .. number),
      },
    }
  end

  before_each(function()
    rebased = {}
    info_messages = {}
    error_messages = {}
    git_calls = {}
    confirm_answer = 1
    confirm_prompts = {}
    _G.octo_buffers = _G.octo_buffers or {}

    chain = {
      entry(1, 1, { head = "feature_1" }),
      entry(2, 2, { base = "feature_1", head = "feature_2" }),
      entry(3, 3, { base = "feature_2", head = "feature_3" }),
    }
    heads = { [1] = "oid1", [2] = "oid2", [3] = "oid3" }
    -- the bottom moved, so the one above it is missing a commit
    behind = { feature_1 = 1, feature_2 = 0 }

    stack = require "octo.stack"
    utils = require "octo.utils"
    gh = require "octo.gh"
    queries = require "octo.gh.queries"
    mutations = require "octo.gh.mutations"
    -- octo.setup() gives up early in the test environment, so the query strings
    -- it would have built are not there yet: the fragments come first
    require("octo.gh.fragments").setup()
    queries.setup()
    mutations.setup()

    utils.info = function(msg)
      table.insert(info_messages, msg)
    end
    utils.error = function(msg)
      table.insert(error_messages, msg)
    end
    utils.get_current_buffer = function()
      return {
        repo = "owner/repo",
        number = 3,
        isPullRequest = function()
          return true
        end,
      }
    end

    original_confirm = vim.fn.confirm
    vim.fn.confirm = function(prompt)
      table.insert(confirm_prompts, prompt)
      return confirm_answer
    end

    -- the local half: remember the commands and answer them
    original_system = vim.system
    vim.system = function(cmd, _, on_exit)
      table.insert(git_calls, table.concat(cmd, " "))
      local answer = { code = 0, stdout = "" }
      if cmd[2] == "rev-parse" and cmd[3] == "--verify" then
        local branch = (cmd[5] or ""):gsub("refs/heads/", "")
        answer.stdout = ({ feature_2 = "oid2", feature_3 = "oid3" })[branch] or ""
        answer.code = answer.stdout == "" and 1 or 0
      elseif cmd[2] == "rev-parse" and cmd[3] == "--show-toplevel" then
        answer.stdout = "/repos/main"
      elseif cmd[2] == "worktree" then
        answer.stdout = "worktree /repos/main\nbranch refs/heads/feature_1\n"
      elseif cmd[2] == "status" then
        answer.stdout = ""
      end
      if on_exit ~= nil then
        on_exit(answer)
      end
      return {
        wait = function()
          return answer
        end,
      }
    end

    -- GitHub: the chain, the rebases, and the head oid that follows each one
    ---@param opts table
    ---@return "rebase"|"head"|"behind"|"chain"
    local function kind_of(opts)
      if opts.f ~= nil and opts.f.method ~= nil then
        return "rebase"
      end
      if opts.jq ~= nil and opts.jq:find "behindBy" then
        return "behind"
      end
      if opts.jq ~= nil and opts.jq:find "headRefOid" then
        return "head"
      end
      return "chain"
    end

    gh.api.graphql = function(opts)
      local cb = opts.opts and opts.opts.cb
      local kind = kind_of(opts)
      if kind == "behind" then
        local parent = (opts.F.parent or ""):gsub("refs/heads/", "")
        cb(tostring(behind[parent] or 0), "", 0)
      elseif kind == "head" then
        local number = tonumber(opts.jq:match "== (%d+)")
        cb(string.format('"%s"', heads[number]), "", 0)
      elseif kind == "chain" then
        cb(vim.json.encode { baseRefName = "master", entries = { nodes = chain } }, "", 0)
      else
        table.insert(rebased, { id = opts.f.id, expected = opts.f.expectedHeadOid, method = opts.f.method })
        local number = tonumber((opts.f.id:gsub("PR_", "")))
        heads[number] = "rebased" .. number -- GitHub moves the branch
        cb("", "", 0)
      end
    end
    stub_kind = kind_of
  end)

  after_each(function()
    vim.fn.confirm = original_confirm
    vim.system = original_system
    package.loaded["octo.stack"] = nil
    package.loaded["octo.utils"] = nil
    package.loaded["octo.gh"] = nil
  end)

  it("rebases every pull request above the one that moved, bottom up", function()
    stack.sync()

    eq(2, #rebased)
    -- the layer just above first, then the one above that
    eq({ id = "PR_2", expected = "oid2", method = "REBASE" }, rebased[1])
    eq({ id = "PR_3", expected = "oid3", method = "REBASE" }, rebased[2])
  end)

  it("asks first, naming what it will rewrite", function()
    stack.sync()

    eq(1, #confirm_prompts)
    assert.is_truthy(confirm_prompts[1]:find("#2", 1, true))
    assert.is_truthy(confirm_prompts[1]:find("#3", 1, true))
    assert.is_falsy(confirm_prompts[1]:find("#1", 1, true)) -- the bottom is not rebased
    assert.is_truthy(confirm_prompts[1]:find("rewritten", 1, true))
  end)

  it("does nothing when the answer is no", function()
    confirm_answer = 2

    stack.sync()

    eq(0, #rebased)
    eq(0, #git_calls)
  end)

  it("starts at the lowest one that is missing something from its parent", function()
    behind = { feature_1 = 0, feature_2 = 1 }

    stack.sync()

    eq(1, #rebased)
    eq("PR_3", rebased[1].id)
  end)

  it("says so when the whole stack is up to date", function()
    behind = { feature_1 = 0, feature_2 = 0 }

    stack.sync()

    eq(0, #rebased)
    eq(0, #confirm_prompts)
    assert.is_truthy(info_messages[#info_messages]:find("already on top", 1, true))
  end)

  it("skips a pull request that is closed or merged", function()
    chain[2].pullRequest.state = "MERGED"
    behind = { feature_1 = 1, feature_2 = 1 }

    stack.sync()

    eq(1, #rebased)
    eq("PR_3", rebased[1].id)
  end)

  it("stops where GitHub refuses, and says the rest were left alone", function()
    local calls = 0
    local original = gh.api.graphql
    gh.api.graphql = function(opts)
      if stub_kind(opts) == "rebase" then
        calls = calls + 1
        if calls == 1 then
          table.insert(rebased, { id = opts.f.id })
          opts.opts.cb("", "cannot be rebased", 1)
          return
        end
      end
      return original(opts)
    end

    stack.sync()

    eq(1, #rebased) -- the one that failed, and nothing above it
    assert.is_truthy(error_messages[#error_messages]:find("left alone", 1, true))
  end)

  it("treats a base that has not moved as nothing to do", function()
    local original = gh.api.graphql
    gh.api.graphql = function(opts)
      if stub_kind(opts) == "rebase" and opts.f.id == "PR_2" then
        table.insert(rebased, { id = opts.f.id })
        opts.opts.cb("", "There are no new commits on the base branch.", 1)
        return
      end
      return original(opts)
    end

    stack.sync()

    -- it carries on up the stack rather than stopping
    eq(2, #rebased)
    eq("PR_3", rebased[2].id)
    eq(0, #error_messages)
  end)

  ---@param predicate fun(): boolean
  local function settled(predicate)
    -- the catch-up runs on the loop once the fetch answers
    vim.wait(500, predicate, 10)
  end

  it("moves the local branches that are exactly what GitHub rebased", function()
    stack.sync()
    settled(function()
      for _, call in ipairs(git_calls) do
        if call:find("fetch --force", 1, true) then
          return true
        end
      end
      return false
    end)

    local fetched = nil
    for _, call in ipairs(git_calls) do
      if call:find("fetch --force", 1, true) then
        fetched = call
      end
    end
    assert.is_not_nil(fetched)
    assert.is_truthy(fetched:find("+refs/heads/feature_2:refs/heads/feature_2", 1, true))
    assert.is_truthy(fetched:find("+refs/heads/feature_3:refs/heads/feature_3", 1, true))
    assert.is_truthy(info_messages[#info_messages - 0]:find("feature_2", 1, true))
  end)

  it("leaves a local branch holding something else where it is", function()
    -- the reader has their own commit on feature_3
    local original_system_stub = vim.system
    vim.system = function(cmd, o, on_exit)
      if cmd[2] == "rev-parse" and cmd[3] == "--verify" and (cmd[5] or ""):find "feature_3" then
        table.insert(git_calls, table.concat(cmd, " "))
        local answer = { code = 0, stdout = "mine" }
        if on_exit then
          on_exit(answer)
        end
        return {
          wait = function()
            return answer
          end,
        }
      end
      return original_system_stub(cmd, o, on_exit)
    end

    stack.sync()
    settled(function()
      return table.concat(info_messages, "\n"):find("Left alone", 1, true) ~= nil
    end)

    local summary = table.concat(info_messages, "\n")
    assert.is_truthy(summary:find("Left alone", 1, true))
    assert.is_truthy(summary:find("feature_3", 1, true))
    for _, call in ipairs(git_calls) do
      if call:find("fetch --force", 1, true) then
        assert.is_falsy(call:find("feature_3:refs/heads/feature_3", 1, true))
      end
    end
  end)

  it("reads the stack from a number when there is no pull request buffer", function()
    utils.get_current_buffer = function()
      return nil
    end
    utils.get_remote_name = function()
      return "owner/repo"
    end

    stack.sync "2"

    eq(2, #rebased) -- the same chain, asked for by number
  end)
end)
