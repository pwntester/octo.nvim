---@diagnostic disable
local hooks = require "octo.hooks"
local eq = assert.are.same

describe("Hooks module:", function()
  before_each(function()
    hooks.clear()
  end)

  describe("register", function()
    it("adds a hook under the given name.", function()
      local fn = function(data, next)
        next(data)
      end
      hooks.register("test_hook", fn)
      hooks.run("test_hook", { value = 1 }, function(result)
        eq(result.value, 1)
      end)
    end)
  end)

  describe("run", function()
    it("passes data through a single hook.", function()
      hooks.register("mutate", function(data, next)
        data.value = data.value + 1
        next(data)
      end)
      hooks.run("mutate", { value = 1 }, function(result)
        eq(result.value, 2)
      end)
    end)

    it("chains multiple hooks in registration order.", function()
      local order = {}
      hooks.register("chain", function(data, next)
        table.insert(order, "a")
        next(data)
      end)
      hooks.register("chain", function(data, next)
        table.insert(order, "b")
        next(data)
      end)
      hooks.run("chain", {}, function()
        eq(order, { "a", "b" })
      end)
    end)

    it("mutates data across the chain.", function()
      hooks.register("mutate", function(data, next)
        data.body = data.body .. " middle"
        next(data)
      end)
      hooks.register("mutate", function(data, next)
        data.body = data.body .. " end"
        next(data)
      end)
      hooks.run("mutate", { body = "start" }, function(result)
        eq(result.body, "start middle end")
      end)
    end)

    it("calls done immediately when no hooks registered.", function()
      local called = false
      hooks.run("unregistered", { x = 1 }, function(result)
        called = true
        eq(result.x, 1)
      end)
      assert.is_true(called)
    end)

    it("stalls if a hook never calls next.", function()
      hooks.register("stall", function(_, _) end)
      local called = false
      hooks.run("stall", {}, function()
        called = true
      end)
      assert.is_false(called)
    end)

    it("supports a single hook skipping optional args.", function()
      hooks.register("single", function(data, next)
        data.ok = true
        next(data)
      end)
      hooks.run("single", { ok = false }, function(result)
        assert.is_true(result.ok)
      end)
    end)
  end)

  describe("clear", function()
    it("removes hooks for a specific name.", function()
      hooks.register("temp", function(data, next)
        next(data)
      end)
      hooks.clear "temp"
      local called = false
      hooks.run("temp", {}, function()
        called = true
      end)
      assert.is_true(called)
      -- no hooks intercept so done calls immediately
    end)

    it("removes all hooks when called without a name.", function()
      hooks.register("a", function(data, next)
        next(data)
      end)
      hooks.register("b", function(data, next)
        next(data)
      end)
      hooks.clear()
      local called_a = false
      local called_b = false
      hooks.run("a", {}, function()
        called_a = true
      end)
      hooks.run("b", {}, function()
        called_b = true
      end)
      assert.is_true(called_a)
      assert.is_true(called_b)
    end)
  end)
end)
