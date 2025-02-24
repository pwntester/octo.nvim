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
  it("Replace mapping default", function()
    local args = {}
    local opts = {
      remove_label = "Some label",
    }
    gh.insert_args(args, opts)
    local expected = {
      "--remove_label",
      "Some label",
    }
    eq(args, expected)
  end)
  it("Replace mapping underscores", function()
    local args = {}
    local opts = {
      remove_label = "Some label",
    }
    gh.insert_args(args, opts, { ["_"] = "-" })
    local expected = {
      "--remove-label",
      "Some label",
    }
    eq(args, expected)
  end)
  it("Replace mapping underscores boolean", function()
    local args = {}
    local opts = {
      remove_milestone = true,
    }
    gh.insert_args(args, opts, { ["_"] = "-" })
    local expected = {
      "--remove-milestone",
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

local tables_have_same_elements = function(t1, t2)
  if #t1 ~= #t2 then
    return false
  end
  for _, v in ipairs(t1) do
    if not vim.tbl_contains(t2, v) then
      return false
    end
  end
  for _, v in ipairs(t2) do
    if not vim.tbl_contains(t1, v) then
      return false
    end
  end
  return true
end

local assert_tables_have_same_elements = function(t1, t2)
  assert(
    tables_have_same_elements(t1, t2),
    string.format("Expected tables to have the same elements:\n%s\n%s", vim.inspect(t1), vim.inspect(t2))
  )
end

describe("REST API args", function()
  it("no args", function()
    local actual = gh.create_rest_args(nil, {})
    eq(actual, nil)
  end)
  it("Endpoint is required", function()
    local actual = gh.create_rest_args(nil, { format = { owner = "pwntester" }, json = "id", jq = ".id" })
    eq(actual, nil)
  end)
  it("Returns table with untouched endpoint", function()
    local actual = gh.create_rest_args("GET", {
      "repos/pwntester/octo.nvim/pulls",
      jq = ".[].number",
      paginate = true,
    })
    assert_tables_have_same_elements(actual, {
      "api",
      "--method",
      "GET",
      "repos/pwntester/octo.nvim/pulls",
      "--jq",
      ".[].number",
      "--paginate",
    })
  end)
  it("Returns table with formated endpoint", function()
    local actual = gh.create_rest_args("GET", {
      "repos/{owner}/{name}/pulls",
      format = { owner = "pwntester", name = "octo.nvim" },
      jq = ".[].number",
      paginate = true,
    })
    assert_tables_have_same_elements(actual, {
      "api",
      "--method",
      "GET",
      "repos/pwntester/octo.nvim/pulls",
      "--jq",
      ".[].number",
      "--paginate",
    })
  end)
end)

describe("create_graphql_opts:", function()
  local query = "example query"
  local login = "pwntester"
  local repo = "octo.nvim"
  local jq = ".data.user.login"

  it("previous behavior", function()
    local actual = gh.create_graphql_opts {
      query = query,
      fields = { login = login, repo = repo },
      jq = jq,
    }

    eq(actual.f.query, query)
    eq(actual.query, nil)
    eq(actual.F.login, login)
    eq(actual.F.repo, repo)
    eq(actual.fields, nil)
    eq(actual.jq, jq)
  end)

  it("query is required", function()
    local actual = gh.create_graphql_opts {
      f = { login = login },
    }
    eq(actual, nil)
  end)

  it("query added to f", function()
    local actual = gh.create_graphql_opts {
      query = query,
      f = { login = login },
    }
    eq(actual.f.query, query)
    eq(actual.query, nil)
    --- Stays the same
    eq(actual.f.login, login)
  end)

  it("fields appended to F", function()
    local actual = gh.create_graphql_opts {
      query = query,
      fields = { login = login },
      F = { repo = repo },
    }
    eq(actual.F.login, login)
    eq(actual.F.repo, repo)
    eq(actual.fields, nil)
  end)

  it("other fields stay", function()
    local actual = gh.create_graphql_opts {
      query = query,
      raw_field = { login = login },
      F = { repo = repo },
    }
    eq(actual.raw_field.login, login)
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
