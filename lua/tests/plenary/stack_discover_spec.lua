---@diagnostic disable
local eq = assert.are.same

describe("Octo stack discovery:", function()
  local stack
  local gh
  local utils
  local view_opts
  local list_opts
  local link_opts
  local previewed
  local error_messages

  -- #1 (master <- a) <- #2 (a <- b) <- #3 (b <- c), plus an unrelated #9
  local function make_prs()
    return {
      { number = 2, title = "Middle", state = "OPEN", headRefName = "b", baseRefName = "a" },
      { number = 9, title = "Unrelated", state = "OPEN", headRefName = "z", baseRefName = "master" },
      { number = 1, title = "Bottom", state = "OPEN", headRefName = "a", baseRefName = "master" },
      { number = 3, title = "Top", state = "OPEN", headRefName = "c", baseRefName = "b" },
    }
  end

  local function chain_numbers(chain)
    local numbers = {}
    for _, pr in ipairs(chain) do
      table.insert(numbers, pr.number)
    end
    return numbers
  end

  before_each(function()
    view_opts = nil
    list_opts = nil
    link_opts = nil
    previewed = nil
    error_messages = {}

    stack = require "octo.stack"
    gh = require "octo.gh"
    utils = require "octo.utils"

    gh.stack = {
      view = function(opts)
        view_opts = opts
      end,
      link = function(opts)
        link_opts = opts
      end,
    }
    gh.pr = {
      list = function(opts)
        list_opts = opts
      end,
    }

    utils.get_current_buffer = function()
      return {
        number = 2,
        repo = "owner/repo",
        isPullRequest = function()
          return true
        end,
        pullRequest = function()
          return { title = "Middle", state = "OPEN", headRefName = "b", baseRefName = "a" }
        end,
      }
    end
    utils.get_remote_name = function()
      return "owner/repo"
    end
    utils.info = function() end
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

  describe("discover_stack", function()
    it("finds the full chain from a middle PR, bottom first", function()
      local chain = stack.discover_stack(make_prs(), 2)
      eq({ 1, 2, 3 }, chain_numbers(chain))
    end)

    it("finds the same chain from the bottom PR", function()
      local chain = stack.discover_stack(make_prs(), 1)
      eq({ 1, 2, 3 }, chain_numbers(chain))
    end)

    it("returns nil for a PR with no stackable neighbors", function()
      eq(nil, stack.discover_stack(make_prs(), 9))
    end)

    it("returns nil for an unknown PR", function()
      eq(nil, stack.discover_stack(make_prs(), 42))
    end)

    it("stops the upward walk when a branch has several dependent PRs", function()
      local prs = make_prs()
      table.insert(prs, { number = 4, title = "Sibling", state = "OPEN", headRefName = "d", baseRefName = "b" })
      -- both #3 and #4 target b: the chain cannot extend above #2
      local chain = stack.discover_stack(prs, 1)
      eq({ 1, 2 }, chain_numbers(chain))
    end)

    it("returns the fork candidates when several PRs chain onto the anchor", function()
      local prs = {
        { number = 1, title = "Parent", state = "OPEN", headRefName = "feat-parent", baseRefName = "master" },
        { number = 2, title = "Child A", state = "OPEN", headRefName = "feat-child-a", baseRefName = "feat-parent" },
        { number = 3, title = "Child B", state = "OPEN", headRefName = "feat-child-b", baseRefName = "feat-parent" },
      }
      local chain, forks = stack.discover_stack(prs, 1)
      eq(nil, chain)
      eq(2, #forks)
      eq(2, forks[1].number)
      eq(3, forks[2].number)
    end)

    it("terminates on base-branch cycles", function()
      local prs = {
        { number = 1, title = "A", state = "OPEN", headRefName = "a", baseRefName = "b" },
        { number = 2, title = "B", state = "OPEN", headRefName = "b", baseRefName = "a" },
      }
      local chain = stack.discover_stack(prs, 1)
      eq(2, #chain)
    end)
  end)

  describe("create fallback", function()
    local function drive_to_discovery()
      stack.create()
      view_opts.opts.cb("", "not part of a stack", 2)
    end

    it("falls back to PR discovery when no local stack exists", function()
      drive_to_discovery()
      assert.is_not_nil(list_opts)
      assert.is_truthy(list_opts.json:find("baseRefName", 1, true))
    end)

    it("previews the discovered chain and links it on confirm", function()
      drive_to_discovery()
      list_opts.opts.cb(vim.json.encode(make_prs()), "", 0)

      assert.is_not_nil(previewed)
      eq("master", previewed.stack.trunk)
      eq(3, #previewed.stack.branches)
      eq("a", previewed.stack.branches[1].name)
      eq(true, previewed.stack.branches[2].isCurrent)

      previewed.on_confirm()
      assert.is_not_nil(link_opts)
      eq(1, link_opts[1])
      eq(2, link_opts[2])
      eq(3, link_opts[3])
    end)

    it("errors when no chain exists around the current PR", function()
      utils.get_current_buffer = function()
        return {
          number = 9,
          repo = "owner/repo",
          isPullRequest = function()
            return true
          end,
          pullRequest = function()
            return { title = "Unrelated", state = "OPEN", headRefName = "z", baseRefName = "master" }
          end,
        }
      end
      drive_to_discovery()
      list_opts.opts.cb(vim.json.encode(make_prs()), "", 0)
      eq(nil, previewed)
      eq(1, #error_messages)
      assert.is_truthy(error_messages[1]:find("gh stack init", 1, true))
    end)

    it("asks which PR continues the stack when several chain onto the anchor", function()
      utils.get_current_buffer = function()
        return {
          number = 1,
          repo = "owner/repo",
          isPullRequest = function()
            return true
          end,
          pullRequest = function()
            return { title = "Parent", state = "OPEN", headRefName = "feat-parent", baseRefName = "master" }
          end,
        }
      end
      local select_items, select_prompt
      local original_select = vim.ui.select
      vim.ui.select = function(items, opts, cb)
        select_items = items
        select_prompt = opts.prompt
        cb(items[2]) -- the user picks Child B
      end

      drive_to_discovery()
      list_opts.opts.cb(
        vim.json.encode {
          { number = 1, title = "Parent", state = "OPEN", headRefName = "feat-parent", baseRefName = "master" },
          { number = 2, title = "Child A", state = "OPEN", headRefName = "feat-child-a", baseRefName = "feat-parent" },
          { number = 3, title = "Child B", state = "OPEN", headRefName = "feat-child-b", baseRefName = "feat-parent" },
        },
        "",
        0
      )
      vim.ui.select = original_select

      eq(2, #select_items)
      assert.is_truthy(select_prompt:find("chain onto", 1, true))
      assert.is_not_nil(previewed)
      eq(2, #previewed.stack.branches)
      eq("feat-parent", previewed.stack.branches[1].name)
      eq(true, previewed.stack.branches[1].isCurrent)
      eq("feat-child-b", previewed.stack.branches[2].name)
    end)

    it("resolves the current PR from the git branch outside PR buffers", function()
      utils.get_current_buffer = function()
        return nil
      end
      stack.current_branch = function()
        return "c"
      end
      drive_to_discovery()
      list_opts.opts.cb(vim.json.encode(make_prs()), "", 0)
      assert.is_not_nil(previewed)
      eq(true, previewed.stack.branches[3].isCurrent)
    end)
  end)
end)
