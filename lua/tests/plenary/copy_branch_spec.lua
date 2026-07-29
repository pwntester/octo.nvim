---@diagnostic disable
local utils = require "octo.utils"
local eq = assert.are.same

describe("utils.copy_branch:", function()
  local original_info = utils.info
  local original_setreg = vim.fn.setreg
  local info_messages

  before_each(function()
    info_messages = {}
    utils.info = function(msg)
      table.insert(info_messages, msg)
    end
    vim.fn.setreg("z", "", "c")
  end)

  after_each(function()
    utils.info = original_info
    vim.fn.setreg = original_setreg
  end)

  it("writes the branch name to the given register", function()
    utils.copy_branch("feature/foo", "z")

    eq("feature/foo", vim.fn.getreg "z")
  end)

  it("names the register in the notification when it is not the clipboard", function()
    utils.copy_branch("feature/foo", "z")

    eq({ "Copied branch 'feature/foo' (z register)" }, info_messages)
  end)

  it("defaults to the system clipboard register", function()
    local register
    vim.fn.setreg = function(reg)
      register = reg
    end

    utils.copy_branch "feature/foo"

    eq("+", register)
    eq({ "Copied branch 'feature/foo' to the system clipboard (+ register)" }, info_messages)
  end)
end)

describe("commands.copy_branch:", function()
  local commands = require "octo.commands"

  local original_get_current_buffer = utils.get_current_buffer
  local original_copy_branch = utils.copy_branch
  local original_error = utils.error

  local copied
  local error_messages

  local function stub_pr_buffer(head_ref_name, base_ref_name)
    utils.get_current_buffer = function()
      return {
        isPullRequest = function()
          return true
        end,
        pullRequest = function()
          return { headRefName = head_ref_name, baseRefName = base_ref_name }
        end,
      }
    end
  end

  before_each(function()
    copied = {}
    error_messages = {}
    utils.copy_branch = function(name)
      table.insert(copied, name)
    end
    utils.error = function(msg)
      table.insert(error_messages, msg)
    end
  end)

  after_each(function()
    utils.get_current_buffer = original_get_current_buffer
    utils.copy_branch = original_copy_branch
    utils.error = original_error
  end)

  it("copies the head branch when given no argument", function()
    stub_pr_buffer("feature/foo", "main")

    commands.copy_branch()

    eq({ "feature/foo" }, copied)
    eq({}, error_messages)
  end)

  it("copies the head branch when asked explicitly", function()
    stub_pr_buffer("feature/foo", "main")

    commands.copy_branch "head"

    eq({ "feature/foo" }, copied)
    eq({}, error_messages)
  end)

  it("copies the base branch", function()
    stub_pr_buffer("feature/foo", "main")

    commands.copy_branch "base"

    eq({ "main" }, copied)
    eq({}, error_messages)
  end)

  it("rejects an unrecognized argument", function()
    stub_pr_buffer("feature/foo", "main")

    commands.copy_branch "foo"

    eq({}, copied)
    eq({ "Invalid branch: 'foo'. Expected 'head' or 'base'" }, error_messages)
  end)

  it("errors when the ref name is blank", function()
    stub_pr_buffer("", "main")

    commands.copy_branch()

    eq({}, copied)
    eq({ "No head branch found" }, error_messages)
  end)

  it("errors when the base ref name is blank", function()
    stub_pr_buffer("feature/foo", "")

    commands.copy_branch "base"

    eq({}, copied)
    eq({ "No base branch found" }, error_messages)
  end)

  it("errors outside a pull request buffer", function()
    utils.get_current_buffer = function()
      return nil
    end

    commands.copy_branch "base"

    eq({}, copied)
    eq({ "Not a Pull Request buffer" }, error_messages)
  end)

  it("is registered as the pr branch action", function()
    eq("function", type(commands.commands.pr.branch))
    eq(commands.copy_branch, commands.commands.pr.branch)
  end)
end)

describe("commands.octo dispatcher for pr branch:", function()
  local commands = require "octo.commands"

  local original_get_current_buffer = utils.get_current_buffer
  local original_copy_branch = utils.copy_branch

  local copied

  local function stub_pr_buffer(head_ref_name, base_ref_name)
    utils.get_current_buffer = function()
      return {
        isPullRequest = function()
          return true
        end,
        pullRequest = function()
          return { headRefName = head_ref_name, baseRefName = base_ref_name }
        end,
      }
    end
  end

  before_each(function()
    copied = {}
    utils.copy_branch = function(name)
      table.insert(copied, name)
    end
  end)

  after_each(function()
    utils.get_current_buffer = original_get_current_buffer
    utils.copy_branch = original_copy_branch
  end)

  it("copies the head branch through :Octo pr branch", function()
    stub_pr_buffer("feature/foo", "main")

    commands.octo("pr", "branch")

    eq({ "feature/foo" }, copied)
  end)

  it("copies the base branch through :Octo pr branch base", function()
    stub_pr_buffer("feature/foo", "main")

    commands.octo("pr", "branch", "base")

    eq({ "main" }, copied)
  end)
end)

describe("pr_options menu branch entries:", function()
  local mappings = require "octo.mappings"

  local original_get_current_buffer = utils.get_current_buffer
  local original_copy_branch = utils.copy_branch
  local original_select = vim.ui.select

  local copied
  local offered

  before_each(function()
    copied = {}
    offered = {}
    utils.get_current_buffer = function()
      return {
        isPullRequest = function()
          return true
        end,
        pullRequest = function()
          return { headRefName = "feature/foo", baseRefName = "main" }
        end,
      }
    end
    utils.copy_branch = function(name)
      table.insert(copied, name)
    end
  end)

  after_each(function()
    utils.get_current_buffer = original_get_current_buffer
    utils.copy_branch = original_copy_branch
    vim.ui.select = original_select
  end)

  --- Opens the pr_options menu and picks `label`, capturing every offered entry.
  local function choose(label)
    vim.ui.select = function(items, _opts, on_choice)
      offered = items
      on_choice(label)
    end
    mappings.pr_options()
  end

  it("offers both branch entries", function()
    choose(nil)

    eq(true, vim.tbl_contains(offered, "Copy Head Branch"))
    eq(true, vim.tbl_contains(offered, "Copy Base Branch"))
  end)

  it("copies the head branch when Copy Head Branch is chosen", function()
    choose "Copy Head Branch"

    eq({ "feature/foo" }, copied)
  end)

  it("copies the base branch when Copy Base Branch is chosen", function()
    choose "Copy Base Branch"

    eq({ "main" }, copied)
  end)
end)
