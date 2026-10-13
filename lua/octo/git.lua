---@class OctoGitRevParseOpts
---@field abbrev_ref? string | boolean
---@field [integer]? string
---@field opts? OctoRuntimeOpts
---@field args? table

---@class OctoGitStatusOpts
---@field short? boolean
---@field branch? boolean
---@field porcelain? boolean
---@field untracked_files? string
---@field [integer]? string
---@field opts? OctoRuntimeOpts
---@field args? table

---@class OctoGitCheckoutOpts
---@field b? string
---@field B? string
---@field track? boolean
---@field detach? boolean
---@field [integer]? string
---@field opts? OctoRuntimeOpts
---@field args? table

---@class OctoGitFetchOpts
---@field all? boolean
---@field prune? boolean
---@field tags? boolean
---@field [integer]? string
---@field opts? OctoRuntimeOpts
---@field args? table

---@class OctoGitPullOpts
---@field rebase? boolean
---@field ff_only? boolean
---@field [integer]? string
---@field opts? OctoRuntimeOpts
---@field args? table

---@class OctoGitPushOpts
---@field set_upstream? boolean
---@field force_with_lease? boolean
---@field tags? boolean
---@field [integer]? string
---@field opts? OctoRuntimeOpts
---@field args? table

---@class OctoGitBranchOpts
---@field all? boolean
---@field remotes? boolean
---@field delete? boolean
---@field move? boolean
---@field [integer]? string
---@field opts? OctoRuntimeOpts
---@field args? table

---@class OctoGitRemoteOpts
---@field verbose? boolean
---@field [integer]? string
---@field opts? OctoRuntimeOpts
---@field args? table

---@class OctoGitConfigOpts
---@field get_regexp? string
---@field [integer]? string
---@field opts? OctoRuntimeOpts
---@field args? table

---@class OctoGitShowOpts
---@field [integer]? string
---@field opts? OctoRuntimeOpts
---@field args? table

---@class OctoGitMergeOpts
---@field squash? boolean
---@field no_ff? boolean
---@field abort? boolean
---@field [integer]? string
---@field opts? OctoRuntimeOpts
---@field args? table

---@class OctoGitLogOpts
---@field oneline? boolean
---@field decorate? boolean
---@field graph? boolean
---@field max_count? number
---@field pretty? string
---@field [integer]? string
---@field opts? OctoRuntimeOpts
---@field args? table

---@class OctoGit
---@field rev_parse fun(opts?: OctoGitRevParseOpts): OctoProcessResult
---@field status fun(opts?: OctoGitStatusOpts): OctoProcessResult
---@field checkout fun(opts?: OctoGitCheckoutOpts): OctoProcessResult
---@field fetch fun(opts?: OctoGitFetchOpts): OctoProcessResult
---@field pull fun(opts?: OctoGitPullOpts): OctoProcessResult
---@field push fun(opts?: OctoGitPushOpts): OctoProcessResult
---@field branch fun(opts?: OctoGitBranchOpts): OctoProcessResult
---@field remote fun(opts?: OctoGitRemoteOpts): OctoProcessResult
---@field config fun(opts?: OctoGitConfigOpts): OctoProcessResult
---@field show fun(opts?: OctoGitShowOpts): OctoProcessResult
---@field merge fun(opts?: OctoGitMergeOpts): OctoProcessResult
---@field log fun(opts?: OctoGitLogOpts): OctoProcessResult
---@field [string] any

---@type OctoGit
local git = require("octo.process").factory "git"

return git
