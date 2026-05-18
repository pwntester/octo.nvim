--- Async chainable interception hook registry.
--- Hooks allow plugins and user config to intercept and mutate data before
--- octo.nvim performs an API call or action. Each hook receives the current
--- payload and a `next` callback — calling `next(mutated_data)` passes control
--- to the next hook in the chain, following an Express.js / Koa middleware pattern.
--- If no hook calls `next` the chain stalls; the final `done` callback is never
--- invoked and the operation is effectively cancelled.

---@class OctoBeforeReviewSubmitData
---@field review_id string
---@field action string
---@field body string
---@field pull_request { number: number, repo: string, head_ref_name: string, diff: string }

---@alias OctoHookFn fun(data: table, next: fun(table?))

---@alias OctoHooksConfig { before_review_submit?: fun(data: OctoBeforeReviewSubmitData, next: fun(data: OctoBeforeReviewSubmitData)) }

local registry = {} ---@type table<string, OctoHookFn[]>

local M = {}

--- Register an interception hook.
--- The function will be called in registration order when `run` is invoked for `name`.
--- @param name string  Hook identifier (e.g. `"before_review_submit"`).
--- @param fn OctoHookFn  Handler. Call `next(modified_data)` to continue the chain.
function M.register(name, fn)
  registry[name] = registry[name] or {}
  table.insert(registry[name], fn)
end

--- Run the hook chain for `name` with the given `data`.
--- Each registered hook receives `(data, next)`. When a hook calls
--- `next(mutated)`, the mutated value is passed to the next hook.
--- After the last hook calls `next`, `done` receives the final payload.
--- If no hooks are registered `done` is called immediately with the original data.
--- @param name string  Hook identifier to trigger.
--- @param data table  Initial payload to pass through the chain.
--- @param done fun(result: table)  Final callback receiving the (possibly mutated) payload.
function M.run(name, data, done)
  local chain = registry[name] or {}
  if #chain == 0 then
    return done(data)
  end
  local i = 0
  local function step(result)
    i = i + 1
    if i > #chain then
      return done(result)
    end
    chain[i](result or data, step)
  end
  step(data)
end

--- Clear all hooks, or hooks for a specific name.
--- @param name? string  If provided, only hooks registered under this name are cleared.
function M.clear(name)
  if name then
    registry[name] = nil
  else
    registry = {}
  end
end

return M
