---
name: timeline-items
description: >
  Details about timeline items for issues and Pull Requests and how to create and modify.
---

These can be found under GraphQL

`IssueTimelineItems`
`PullRequestTimelineItems`

Use the `lookup-graphql-information` skill if needing more information about them.

## Previous implementations

There is the label `timelineItems` on GitHub that can be used to reference other similar PRs.

For example, `gh pr list --label timelineItems --state closed` shows all of the previous PRs.

## Files involved

The process usually includes changing these files:

```
lua/octo/gh/fragments.lua
lua/octo/gh/queries.lua
lua/octo/ui/writers.lua
lua/octo/utils.lua
```

Please also include any changes to the example-timeline file that will help debug:

```
scripts/example-timeline.lua
```

Please use typing for the new types.

## Fragment Registry (Issue #1365)

Timeline item fragments are managed through a **registry** in `lua/octo/gh/fragments.lua`.
This replaced the previous approach of manually appending raw strings in two places.

### Architecture

The registry lives at module level (outside `setup()`) so external code can register fragments
before `setup()` is called. Two separate registries exist:

- `M._issue_timeline_registry` — for `IssueTimelineItemsConnection`
- `M._pr_timeline_registry` — for `PullRequestTimelineItemsConnection`

Each entry is an `octo.TimelineFragmentEntry`:

```lua
---@class octo.TimelineFragmentEntry
---@field spread string              Fragment name, e.g. "AssignedEventFragment"
---@field definition string          Full GraphQL fragment definition string
---@field condition? fun():boolean   Optional gate evaluated at setup() time
```

### Public API

```lua
M.register_issue_timeline_item(spread_name, definition, condition?)
M.register_pull_request_timeline_item(spread_name, definition, condition?)
```

- **Deduplication**: registering the same `spread_name` twice is safe — later calls are ignored.
- **`condition`**: optional `fun():boolean`. If it returns `false` at `setup()` time, the fragment
  spread and definition are omitted from the query entirely.

Two helper functions build the final definition strings consumed by `queries.lua`:

```lua
M.get_issue_timeline_definitions()   -- returns string
M.get_pr_timeline_definitions()      -- returns string
```

These are called in `queries.lua` at the end of the `..` chain for the `issue` and
`pull_request` queries respectively.

### Adding a new timeline item

1. Define the fragment string as `M.my_event = [[ fragment MyEventFragment on MyEvent { ... } ]]`
   inside `M.setup()` in `lua/octo/gh/fragments.lua`, near the other event definitions.

2. Seed it into the appropriate registry, also inside `M.setup()`, in the `issue_builtin` or
   `pr_builtin` table. Pass a `condition` if the type is not universally available:

   ```lua
   -- Always available:
   { "MyEventFragment", M.my_event },

   -- github.com only (not on GHES) — pass not_enterprise directly:
   { "MyEventFragment", M.my_event, not_enterprise },

   -- Gated on a config flag:
   { "MyEventFragment", M.my_event, function() return config.values.some_flag end },
   ```

3. Add a `---@class octo.fragments.MyEvent` annotation above the fragment definition.

4. Add `octo.fragments.MyEvent` to the `---@alias octo.IssueTimelineItem` or
   `---@alias octo.PullRequestTimelineItem` union type annotation.

5. Handle the new `__typename` in `lua/octo/ui/writers.lua` and/or `lua/octo/utils.lua`.

6. Update `scripts/example-timeline.lua` to include a sample of the new event for debugging.

> **Note**: `queries.lua` does **not** need to be changed for new timeline items — the registry
> and `get_*_timeline_definitions()` handle appending definitions automatically.

### Enterprise compatibility (label: "Enterprise compat")

GHES instances run older GraphQL API versions that lack certain types. Fragments for those
types must carry a condition that gates them out when `github_hostname` is non-empty:

```lua
function() return not is_enterprise() end
-- where is_enterprise() = config.values.github_hostname ~= ""
```

Known GHES-incompatible issue timeline fragments (issues #1153):
`PinnedEvent`, `UnpinnedEvent`, `SubIssueAddedEvent`, `SubIssueRemovedEvent`,
`ParentIssueAddedEvent`, `ParentIssueRemovedEvent`, `IssueTypeAddedEvent`,
`IssueTypeRemovedEvent`, `IssueTypeChangedEvent`, `BlockedByAddedEvent`,
`BlockedByRemovedEvent`, `BlockingAddedEvent`, `BlockingRemovedEvent`, `TransferredEvent`

Known GHES-incompatible PR timeline fragments (issues #685, #513):
`AutomaticBaseChangeSucceededEvent`, `BaseRefChangedEvent`, `ConvertToDraftEvent`,
`DeployedEvent`, `HeadRefDeletedEvent`, `HeadRefRestoredEvent`, `HeadRefForcePushedEvent`,
`AutoSquashEnabledEvent`, `AutoMergeEnabledEvent`, `AutoMergeDisabledEvent`

When adding a new type, check the GitHub Enterprise Server GraphQL changelog to determine
from which GHES version the type is available. If it's newer than ~3.12, gate it.

### Registering a fragment from external code (plugins/user config)

External code that wants to add a custom timeline item should call the registration function
**before** `require("octo").setup()` is called:

```lua
local fragments = require("octo.gh.fragments")

fragments.register_issue_timeline_item(
  "MyCustomEventFragment",
  [[
    fragment MyCustomEventFragment on MyCustomEvent {
      actor { login }
      createdAt
    }
  ]],
  -- Optional condition: only include on github.com
  function()
    return require("octo.config").values.github_hostname == ""
  end
)
```
