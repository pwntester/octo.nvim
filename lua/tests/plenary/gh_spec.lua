local gh = require "octo.gh"
local eq = assert.are.same

describe("insert_args:", function()
  it("true booleans show up as flags", function()
    local args = {}
    local opts = {
      slurp = false,
      paginate = true,
    }
    gh.insert_args(args, opts)
    local expected = {
      "--paginate",
    }
    eq(args, expected)
  end)
  it("single characters have single hyphen", function()
    local args = {}
    local opts = {
      F = {
        query = "query",
      },
    }
    gh.insert_args(args, opts)
    local expected = {
      "-F",
      "query=query",
    }
    eq(args, expected)
  end)
  it("non-single changes have two hyphens", function()
    local args = {}
    local opts = {
      jq = ".",
    }
    gh.insert_args(args, opts)
    local expected = {
      "--jq",
      ".",
    }
    eq(args, expected)
  end)
  it("list of fields get brackets", function()
    local args = {}
    local opts = {
      f = {
        items = { "a", "b", "c" },
      },
    }
    gh.insert_args(args, opts)
    local expected = {
      "-f",
      "items[]=a",
      "-f",
      "items[]=b",
      "-f",
      "items[]=c",
    }
    eq(args, expected)
  end)
  it("integer values", function()
    local args = {}
    local opts = {
      f = {
        num_issues = 15,
      },
    }
    gh.insert_args(args, opts)
    local expected = {
      "-f",
      "num_issues=15",
    }
    eq(args, expected)
  end)
end)

describe("CLI commands", function()
  it("gh.<something> returns table", function()
    local commands = {
      "issue",
      "pr",
      "repo",
      "gist",
      "random",
    }

    for _, command in ipairs(commands) do
      local actual = gh[command]
      eq(actual.command, command)
      assert.is_table(actual)
    end
  end)
  it("gh.<something>.<another-thing> is a function", function()
    local subcommands = {
      "list",
      "view",
      "develop",
      "create",
      "random",
    }
    for _, subcommand in ipairs(subcommands) do
      local actual = gh.issue[subcommand]
      assert.is_function(actual)
    end
  end)
end)
