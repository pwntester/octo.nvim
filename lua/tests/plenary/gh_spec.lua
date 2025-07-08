---@diagnostic disable
local gh = require "octo.gh"
local eq = assert.are.same

local function tables_have_same_elements(t1, t2)
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

local function assert_tables_have_same_elements(t1, t2)
  assert(
    tables_have_same_elements(t1, t2),
    string.format("Expected tables to have the same elements:\n%s\n%s", vim.inspect(t1), vim.inspect(t2))
  )
end

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
  it("table of fields parsed correctly", function()
    local args = {}
    local opts = {
      f = {
        items = {
          nested_list = { 1, 2, 3 },
          nested_obj = { first = 1, second = 2 },
          second = 2,
        },
      },
    }
    gh.insert_args(args, opts)
    local expected = {
      "-f",
      "items[nested_list][]=1",
      "-f",
      "items[nested_list][]=2",
      "-f",
      "items[nested_list][]=3",
      "-f",
      "items[nested_obj][first]=1",
      "-f",
      "items[nested_obj][second]=2",
      "-f",
      "items[second]=2",
    }
    assert_tables_have_same_elements(args, expected)
  end)
  it("gh api --help schema example", function()
    local args = {}
    local opts = {
      F = {
        properties = {
          {
            property_name = "environment",
            default_value = "production",
            required = true,
            allowed_values = {
              "staging",
              "production",
            },
          },
        },
      },
    }
    gh.insert_args(args, opts)
    local expected = {
      "-F",
      "properties[][property_name]=environment",
      "-F",
      "properties[][required]=true",
      "-F",
      "properties[][default_value]=production",
      "-F",
      "properties[][allowed_values][]=staging",
      "-F",
      "properties[][allowed_values][]=production",
    }
    assert_tables_have_same_elements(args, expected)
  end)
  it("gh api --help gist example", function()
    local args = {}
    local opts = {
      F = {
        files = {
          ["myfile.txt"] = {
            content = "@myfile.txt",
          },
        },
      },
    }
    gh.insert_args(args, opts)
    local expected = {
      "-F",
      "files[myfile.txt][content]=@myfile.txt",
    }
    eq(args, expected)
  end)
  it("gh api common use case", function()
    local args = {}
    local opts = {
      f = { owner = "pwntester", repo = "octo.nvim", required = true },
      F = { number = 1, total = 100 },
    }
    gh.insert_args(args, opts)
    local expected = {
      "-f",
      "owner=pwntester",
      "-f",
      "repo=octo.nvim",
      "-f",
      "required=true",
      "-F",
      "number=1",
      "-F",
      "total=100",
    }
    assert_tables_have_same_elements(args, expected)
  end)
end)

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
