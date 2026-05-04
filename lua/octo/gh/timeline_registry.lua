--- Timeline writer registry.
---
--- Maps GraphQL __typename values to their rendering behaviour.
--- Populated at startup from writers.lua after all write_* functions are defined.
---
--- Entry shape:
---   writer  fun(bufnr: integer, item: table)  Direct-dispatch writer. Mutually exclusive with `batch`.
---   batch   string                             Name of the local accumulator table in write_timeline_items.
---                                              Mutually exclusive with `writer`.
---
--- Special typenames that receive custom handling in write_timeline_items and are NOT in this
--- registry: "IssueComment", "PullRequestReview".

---@alias octo.TimelineBatchKey
---| "assignment_events"
---| "label_events"
---| "pull_request_commits"
---| "force_pushed_events"
---| "review_requested_events"
---| "review_request_removed_events"
---| "subissue_added_events"
---| "subissue_removed_events"

---@class octo.TimelineWriterEntry
---@field writer? fun(bufnr: integer, item: table)
---@field batch? octo.TimelineBatchKey
---@field sets_prev_event? boolean

local M = {}

---@type table<string, octo.TimelineWriterEntry>
M._registry = {}

--- Register a typename → writer/batch mapping.
--- Safe to call multiple times; later registrations are ignored (dedup by typename).
---@param typename string            GraphQL __typename, e.g. "MergedEvent"
---@param entry    octo.TimelineWriterEntry
function M.register(typename, entry)
  if M._registry[typename] == nil then
    M._registry[typename] = entry
  end
end

--- Look up an entry by typename.
---@param typename string
---@return octo.TimelineWriterEntry?
function M.get(typename)
  return M._registry[typename]
end

return M
