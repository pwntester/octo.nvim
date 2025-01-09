local gh = require "octo.gh"
local eq = assert.are.same

describe("gh", function()
  it("booleans", function()
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
  it("single-char-has-single-hyphen", function()
    local args = {}
    local opts = {
      F = {
        query = "query",
      },
      f = {
        foo = "bar",
      },
    }
    gh.insert_args(args, opts)
    local expected = {
      "-F",
      "query=query",
      "-f",
      "foo=bar",
    }
    eq(args, expected)
  end)
  it("non-single-char-has-two-hyphens", function()
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
  it("list-get-brackets", function()
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
end)
