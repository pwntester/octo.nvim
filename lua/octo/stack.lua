local config = require "octo.config"
local gh = require "octo.gh"
local mutations = require "octo.gh.mutations"
local queries = require "octo.gh.queries"
local utils = require "octo.utils"
local window = require "octo.ui.window"

local M = {}

---@class octo.StackViewPR
---@field number integer
---@field url string
---@field state "OPEN"|"MERGED"|"QUEUED"

---@class octo.StackViewBranch
---@field name string
---@field head string
---@field base string
---@field isCurrent boolean
---@field isMerged boolean
---@field isQueued boolean
---@field needsRebase boolean
---@field pr? octo.StackViewPR

---@class octo.StackView
---@field trunk string
---@field currentBranch string
---@field branches octo.StackViewBranch[] bottom of the stack first

---Build the preview lines for a stack: top of the stack first, trunk last.
---@param stack octo.StackView
---@return string[]
function M.build_stack_preview(stack)
  local lines = {} ---@type string[]
  local needs_rebase = false
  for i = #stack.branches, 1, -1 do
    local branch = stack.branches[i]
    local marker = branch.isCurrent and "▶" or " "
    local pr_info ---@type string
    if branch.pr and branch.pr ~= vim.NIL then
      pr_info = string.format("#%d (%s)", branch.pr.number, branch.pr.state)
    else
      pr_info = "new PR"
    end
    table.insert(lines, string.format(" %s %s · %s", marker, branch.name, pr_info))
    needs_rebase = needs_rebase or branch.needsRebase
  end
  table.insert(lines, string.format(" ○ %s", stack.trunk))
  if needs_rebase then
    table.insert(lines, "")
    table.insert(lines, " ⚠ some branches need a rebase: run 'Octo stack sync' first")
  end
  table.insert(lines, "")
  table.insert(lines, " <CR> create/update stack · q cancel")
  return lines
end

---Show the stack preview in a centered float; call on_confirm when accepted.
---@param stack octo.StackView
---@param on_confirm fun()
function M.show_stack_preview(stack, on_confirm)
  local winid, bufnr = window.create_centered_float {
    header = "Preview stack",
    content = M.build_stack_preview(stack),
    enter = true,
  }
  vim.bo[bufnr].modifiable = false

  local function close()
    window.try_close_wins(winid)
  end

  local mapping_opts = { silent = true, noremap = true, buffer = bufnr }
  vim.keymap.set("n", "q", close, mapping_opts)
  vim.keymap.set("n", "<Esc>", close, mapping_opts)
  vim.keymap.set("n", "<CR>", function()
    close()
    on_confirm()
  end, mapping_opts)
end

---Push the stack branches and create or update their PRs on GitHub.
function M.submit()
  utils.info "Submitting stack..."
  gh.stack.submit {
    auto = true,
    opts = {
      cb = function(output, stderr, exit_code)
        if exit_code == 0 then
          local message = not utils.is_blank(stderr) and stderr or output
          utils.info(utils.is_blank(message) and "Stack submitted" or message)
        else
          utils.error(utils.is_blank(stderr) and "Failed to submit the stack" or stderr)
        end
      end,
    },
  }
end

---@class octo.StackCandidatePR
---@field number integer
---@field title string
---@field state string
---@field headRefName string
---@field baseRefName string

---Walk base/head branch relationships among open PRs to find the dependency
---chain containing the given PR, like GitHub's "Preview stack" banner.
---Returns the chain bottom (closest to the trunk) first, or nil when the PR
---has no stackable neighbors. The upward walk stops when a branch has more
---than one dependent PR, since stacks are strictly linear; those competing
---PRs are returned as the second value so a caller can let the user choose.
---@param prs octo.StackCandidatePR[] the repository's open PRs
---@param start_number integer
---@return octo.StackCandidatePR[]? chain
---@return octo.StackCandidatePR[]? forks # dependent PRs competing at the point the walk stopped
function M.discover_stack(prs, start_number)
  local by_number = {} ---@type table<integer, octo.StackCandidatePR>
  local by_head = {} ---@type table<string, octo.StackCandidatePR>
  local by_base = {} ---@type table<string, octo.StackCandidatePR>
  local base_is_ambiguous = {} ---@type table<string, boolean>
  for _, pr in ipairs(prs) do
    by_number[pr.number] = pr
    by_head[pr.headRefName] = pr
    if by_base[pr.baseRefName] then
      base_is_ambiguous[pr.baseRefName] = true
    else
      by_base[pr.baseRefName] = pr
    end
  end

  local current = by_number[start_number]
  if not current then
    return nil
  end

  local chain = { current }
  local seen = { [current.number] = true } ---@type table<integer, boolean>

  local parent = by_head[current.baseRefName]
  while parent and not seen[parent.number] do
    table.insert(chain, 1, parent)
    seen[parent.number] = true
    parent = by_head[parent.baseRefName]
  end

  local forks = nil ---@type octo.StackCandidatePR[]?
  while true do
    local tail = chain[#chain] ---@type octo.StackCandidatePR
    if base_is_ambiguous[tail.headRefName] then
      forks = {}
      for _, pr in ipairs(prs) do
        if pr.baseRefName == tail.headRefName and not seen[pr.number] then
          table.insert(forks, pr)
        end
      end
      break
    end
    local child = by_base[tail.headRefName]
    if not child or seen[child.number] then
      break
    end
    table.insert(chain, child)
    seen[child.number] = true
  end

  if #chain < 2 then
    return nil, forks
  end
  return chain, forks
end

---Name of the currently checked out git branch, or nil.
---@return string?
function M.current_branch()
  local result = vim.system({ "git", "branch", "--show-current" }, { text = true }):wait()
  if result.code ~= 0 or utils.is_blank(result.stdout) then
    return nil
  end
  return vim.trim(result.stdout)
end

---Link a discovered chain of PRs into a stack on GitHub via gh stack link.
---No local tracking state is created.
---@param chain octo.StackCandidatePR[] bottom first
function M.link(chain)
  utils.info "Creating stack..."
  local opts = { opts = {} }
  for _, pr in ipairs(chain) do
    table.insert(opts, pr.number)
  end
  opts.opts.cb = function(output, stderr, exit_code)
    if exit_code == 0 then
      local message = not utils.is_blank(stderr) and stderr or output
      utils.info(utils.is_blank(message) and "Stack created" or message)
    else
      utils.error(utils.is_blank(stderr) and "Failed to create the stack" or stderr)
    end
  end
  gh.stack.link(opts)
end

---Fallback for create() when no local gh stack exists: detect open PRs whose
---base branches chain onto each other and offer to link them into a stack.
local function preview_discovered_stack()
  local current_number ---@type integer?
  local anchor ---@type octo.StackCandidatePR?
  local buffer = utils.get_current_buffer()
  if buffer and buffer:isPullRequest() then
    local current_repo = utils.get_remote_name()
    if current_repo ~= buffer.repo then
      utils.error(
        string.format("':Octo stack create' must run inside a checkout of %s (current: %s)", buffer.repo, current_repo)
      )
      return
    end
    current_number = buffer.number
    -- the buffer already knows this PR's branches: seed it into the listing
    -- in case it falls outside the listing window (older PRs)
    local node = buffer:pullRequest()
    if node.state == "OPEN" then
      anchor = {
        number = buffer.number,
        title = node.title,
        state = node.state,
        headRefName = node.headRefName,
        baseRefName = node.baseRefName,
      }
    end
  end

  local current_branch = nil ---@type string?
  if not current_number then
    current_branch = M.current_branch()
    if utils.is_blank(current_branch) then
      utils.error "Cannot determine the current PR: open a PR buffer or check out a PR branch"
      return
    end
  end

  gh.pr.list {
    json = "number,title,state,headRefName,baseRefName",
    limit = "1000",
    opts = {
      cb = function(output, stderr, exit_code)
        if exit_code ~= 0 then
          utils.error(utils.is_blank(stderr) and "Failed to list pull requests" or stderr)
          return
        end
        local ok, decoded = pcall(vim.json.decode, output)
        if not ok or utils.is_blank(decoded) then
          utils.error "Failed to parse the pull request list"
          return
        end
        local prs = decoded ---@type octo.StackCandidatePR[]

        if anchor then
          local anchor_listed = false
          for _, pr in ipairs(prs) do
            if pr.number == anchor.number then
              anchor_listed = true
              break
            end
          end
          if not anchor_listed then
            table.insert(prs, anchor)
          end
        end

        if not current_number then
          for _, pr in ipairs(prs) do
            if pr.headRefName == current_branch then
              current_number = pr.number
              break
            end
          end
          if not current_number then
            utils.error(string.format("No open PR found for branch %s", current_branch))
            return
          end
        end

        ---@param chain octo.StackCandidatePR[]
        local function preview_chain(chain)
          local branches = {} ---@type octo.StackViewBranch[]
          for _, pr in ipairs(chain) do
            table.insert(branches, {
              name = pr.headRefName,
              isCurrent = pr.number == current_number,
              needsRebase = false,
              pr = { number = pr.number, state = pr.state, url = "" },
            })
          end
          local stack = {
            trunk = chain[1].baseRefName,
            currentBranch = "",
            branches = branches,
          }
          M.show_stack_preview(stack, function()
            M.link(chain)
          end)
        end

        local chain, forks = M.discover_stack(prs, current_number)
        if chain then
          preview_chain(chain)
          return
        end

        if forks and #forks > 0 then
          -- several PRs chain onto this one: linear stacks need a choice
          vim.ui.select(forks, {
            prompt = "Several PRs chain onto this one — pick the next PR in the stack:",
            format_item = function(pr)
              return string.format("#%d %s (%s)", pr.number, pr.title, pr.headRefName)
            end,
          }, function(choice)
            if not choice then
              return
            end
            local chosen_chain = M.discover_stack(prs, choice.number)
            if not chosen_chain then
              utils.error "Could not build a stack around the selected PR"
              return
            end
            preview_chain(chosen_chain)
          end)
          return
        end

        utils.error "No stackable PRs found: no other open PR chains onto this one. Run 'gh stack init' to start a stack locally."
      end,
    },
  }
end

---@class octo.StackSyncEntry
---@field id string
---@field number integer
---@field title string
---@field state string
---@field baseRefName string
---@field headRefName string
---@field headRefOid string
---@field mergeStateStatus string
---@field position integer

---The chain a pull request sits in, worked out from the base branches of the
---open pull requests, for stacks that were never linked on GitHub.
---@param number integer
---@param cb fun(entries: octo.StackSyncEntry[]): nil
local function discover_chain(number, cb)
  gh.pr.list {
    json = "id,number,title,state,headRefName,baseRefName,headRefOid,mergeStateStatus",
    limit = "1000",
    opts = {
      cb = function(output, stderr, exit_code)
        if exit_code ~= 0 then
          utils.error(utils.is_blank(stderr) and "Failed to list pull requests" or stderr)
          return
        end
        local ok, prs = pcall(vim.json.decode, output)
        if not ok or utils.is_blank(prs) then
          utils.error "Failed to parse the pull request list"
          return
        end
        local chain = M.discover_stack(prs, number)
        if chain == nil or #chain < 2 then
          utils.info "This pull request has nothing stacked on it and nothing under it"
          return
        end
        local entries = {} ---@type octo.StackSyncEntry[]
        for position, pr in ipairs(chain) do
          local entry = pr --[[@as octo.StackSyncEntry]]
          entry.position = position
          table.insert(entries, entry)
        end
        cb(entries)
      end,
    },
  }
end

---Read a stack from GitHub, bottom of the stack first.
---@param repo string
---@param number integer a pull request in the stack
---@param cb fun(entries: octo.StackSyncEntry[]): nil
local function fetch_chain(repo, number, cb)
  local owner, name = utils.split_repo(repo)
  gh.api.graphql {
    query = queries.stack_heads,
    F = { owner = owner, name = name, number = number },
    jq = ".data.repository.pullRequest.stackEntry.stack",
    opts = {
      cb = gh.create_callback {
        failure = function(stderr)
          utils.error(utils.is_blank(stderr) and "Cannot read the stack" or stderr)
        end,
        success = function(output)
          if utils.is_blank(output) or output == "null" then
            -- not linked as a stack on GitHub: the chain of base branches is
            -- still a stack in every way that matters here
            discover_chain(number, cb)
            return
          end
          local stack = vim.json.decode(output)
          local entries = {} ---@type octo.StackSyncEntry[]
          ---@type { position: integer, pullRequest: octo.StackSyncEntry }[]
          local nodes = vim.tbl_get(stack, "entries", "nodes") or {}
          for _, node in ipairs(nodes) do
            local entry = node.pullRequest
            entry.position = node.position
            table.insert(entries, entry)
          end
          table.sort(entries, function(a, b)
            return a.position < b.position
          end)
          if #entries < 2 then
            utils.info "A stack of one has nothing to propagate"
            return
          end
          cb(entries)
        end,
      },
    },
  }
end

---Ask GitHub to rebase a pull request's branch onto its base. Answers once the
---branch has actually moved, which is later than the mutation returns.
---@param repo string
---@param entry octo.StackSyncEntry
---@param cb fun(moved: boolean, message: string?): nil
local function rebase_on_github(repo, entry, cb)
  local owner, name = utils.split_repo(repo)

  ---@param attempts integer
  local function wait_for_move(attempts)
    if attempts <= 0 then
      cb(false, string.format("#%d was asked to rebase but has not moved yet", entry.number))
      return
    end
    gh.api.graphql {
      query = queries.pull_request_head_oid,
      F = { owner = owner, name = name, number = entry.number },
      jq = ".data.repository.pullRequest.headRefOid",
      opts = {
        cb = function(output)
          local head = vim.trim((output or ""):gsub('"', ""))
          if not utils.is_blank(head) and head ~= entry.headRefOid then
            entry.headRefOid = head
            cb(true)
            return
          end
          vim.defer_fn(function()
            wait_for_move(attempts - 1)
          end, 2000)
        end,
      },
    }
  end

  gh.api.graphql {
    query = mutations.update_pull_request_branch,
    f = { id = entry.id, expectedHeadOid = entry.headRefOid, method = "REBASE" },
    opts = {
      cb = function(_, stderr, exit_code)
        if exit_code ~= 0 then
          -- the base has not moved since: nothing to propagate into this one
          if stderr and stderr:find("no new commits", 1, true) then
            cb(true, string.format("#%d was already up to date", entry.number))
            return
          end
          if stderr and stderr:find("expected head", 1, true) then
            cb(false, string.format("#%d moved while syncing: run it again", entry.number))
            return
          end
          cb(false, string.format("#%d could not be rebased: %s", entry.number, vim.trim(stderr or "")))
          return
        end
        -- GitHub queues the rebase, so wait for the branch to move
        wait_for_move(15)
      end,
    },
  }
end

---@param args string[]
---@return string?
local function git_output(args)
  local result = vim.system(args, { text = true }):wait()
  if result.code ~= 0 then
    return nil
  end
  return vim.trim(result.stdout or "")
end

---@param branch string
---@return string?
local function local_sha(branch)
  return git_output { "git", "rev-parse", "--verify", "--quiet", "refs/heads/" .. branch }
end

---Branches checked out in a worktree other than this one: moving their ref from
---under them would leave that worktree looking at a commit it is not on.
---@return table<string, string> branch -> worktree path
local function branches_in_other_worktrees()
  local held = {} ---@type table<string, string>
  local output = git_output { "git", "worktree", "list", "--porcelain" }
  local here = git_output { "git", "rev-parse", "--show-toplevel" }
  if output == nil then
    return held
  end
  local path ---@type string?
  for _, line in ipairs(vim.split(output, "\n")) do
    local worktree = line:match "^worktree (.+)$"
    local branch = line:match "^branch refs/heads/(.+)$"
    if worktree then
      path = worktree
    elseif branch and path ~= nil and path ~= here then
      held[branch] = path
    end
  end
  return held
end

---Bring the local branches in line with what GitHub rewrote. Only branches that
---were exactly what GitHub rebased are moved: anything else is the reader's own
---work, and is left where it is.
---@param rebased { number: integer, branch: string, before: string, after: string }[]
local function local_catch_up(rebased)
  if #rebased == 0 then
    return
  end

  local remote = config.values.default_remote[1] or "origin"
  vim.system({ "git", "fetch", remote }, { text = true }, function()
    vim.schedule(function()
      local current = M.current_branch()
      local held = branches_in_other_worktrees()
      local refspecs = {} ---@type string[]
      local moved = {} ---@type string[]
      local left = {} ---@type string[]
      local reset_current ---@type { branch: string, after: string }?

      for _, item in ipairs(rebased) do
        local sha = local_sha(item.branch)
        if sha == nil or sha == item.after then
          -- no local copy, or already where GitHub is
        elseif sha ~= item.before then
          -- the local branch is not what was rebased: it holds something else
          table.insert(left, item.branch)
        elseif held[item.branch] then
          table.insert(left, item.branch .. " (checked out in " .. held[item.branch] .. ")")
        elseif item.branch == current then
          reset_current = { branch = item.branch, after = item.after }
        else
          table.insert(refspecs, string.format("+refs/heads/%s:refs/heads/%s", item.branch, item.branch))
          table.insert(moved, item.branch)
        end
      end

      if #refspecs > 0 then
        local fetched =
          vim.system(vim.list_extend({ "git", "fetch", "--force", remote }, refspecs), { text = true }):wait()
        if fetched.code ~= 0 then
          for _, branch in ipairs(moved) do
            table.insert(left, branch)
          end
          moved = {}
        end
      end

      if reset_current ~= nil then
        local dirty = git_output { "git", "status", "--porcelain" }
        if utils.is_blank(dirty) then
          local reset = vim.system({ "git", "reset", "--hard", reset_current.after }, { text = true }):wait()
          if reset.code == 0 then
            table.insert(moved, reset_current.branch .. " (checked out here)")
          else
            table.insert(left, reset_current.branch)
          end
        else
          table.insert(left, reset_current.branch .. " (uncommitted changes)")
        end
      end

      if #moved > 0 then
        utils.info("Local branches moved to match GitHub: " .. table.concat(moved, ", "))
      end
      if #left > 0 then
        utils.info("Left alone, they are not what GitHub rebased: " .. table.concat(left, ", "))
      end
    end)
  end)
end

---How many commits of `parent` the branch of `child` has not got. A pull
---request's own merge state says nothing about this: GitHub only calls a branch
---BEHIND when the repository insists branches be current before merging.
---@param repo string
---@param parent string branch
---@param child string branch
---@param cb fun(behind: integer): nil
local function behind_by(repo, parent, child, cb)
  local owner, name = utils.split_repo(repo)
  gh.api.graphql {
    query = queries.ref_behind,
    F = { owner = owner, name = name, parent = "refs/heads/" .. parent, child = child },
    jq = ".data.repository.ref.compare.behindBy",
    opts = {
      cb = function(output, _, exit_code)
        if exit_code ~= 0 then
          cb(0)
          return
        end
        cb(tonumber(vim.trim((output or ""):gsub('"', ""))) or 0)
      end,
    },
  }
end

---What syncing has to rebase: the lowest pull request whose branch is missing
---something from its parent, and every open one above it -- rebasing that one
---leaves the next behind in turn, which is the whole point of a stack.
---@param repo string
---@param entries octo.StackSyncEntry[]
---@param cb fun(plan: octo.StackSyncEntry[]): nil
local function plan_rebases(repo, entries, cb)
  ---@param position integer
  local function look(position)
    if position > #entries then
      cb {}
      return
    end
    local entry = entries[position]
    if entry.state ~= "OPEN" then
      look(position + 1)
      return
    end
    behind_by(repo, entries[position - 1].headRefName, entry.headRefName, function(behind)
      if behind == 0 then
        look(position + 1)
        return
      end
      local plan = {} ---@type octo.StackSyncEntry[]
      for above = position, #entries do
        if entries[above].state == "OPEN" then
          table.insert(plan, entries[above])
        end
      end
      cb(plan)
    end)
  end

  look(2)
end

---@param plan octo.StackSyncEntry[]
---@return boolean
local function confirm_rebase(plan)
  local lines = { string.format("Rebase %d pull request(s) on GitHub, bottom up?", #plan) }
  for _, entry in ipairs(plan) do
    table.insert(lines, string.format("  #%d %s", entry.number, entry.title))
  end
  table.insert(lines, "")
  table.insert(lines, "Their remote branches are rewritten. Local copies of them")
  table.insert(lines, "are moved to match afterwards where it is safe to do so.")
  return vim.fn.confirm(table.concat(lines, "\n"), "&Yes\n&No", 2) == 1
end

---Propagate a change up a stack, on GitHub. Every pull request above the one
---that moved is rebased onto its parent, in order, whichever branch the reader
---happens to be on: the work is the same wherever it is asked for.
---@param ... string a pull request number, when there is no buffer to read it from
function M.sync(...)
  local number ---@type integer?
  for _, arg in ipairs { ... } do
    number = number or tonumber(arg)
  end

  local buffer = utils.get_current_buffer()
  local found = buffer and buffer.repo or utils.get_remote_name()
  -- a type check rather than `is_blank`: it narrows for the language server
  if type(found) ~= "string" or found == "" then
    utils.error "Cannot tell which repository to sync"
    return
  end
  local repo = found
  if number == nil and buffer ~= nil and buffer:isPullRequest() then
    number = buffer.number
  end

  ---@param pull_number integer
  local function run(pull_number)
    fetch_chain(repo, pull_number, function(entries)
      plan_rebases(repo, entries, function(plan)
        if #plan == 0 then
          utils.info "Every pull request in the stack is already on top of its parent"
          return
        end
        if not confirm_rebase(plan) then
          return
        end

        local rebased = {} ---@type { number: integer, branch: string, before: string, after: string }[]
        local function step(index)
          if index > #plan then
            utils.info(string.format("Rebased %d of %d on GitHub", #rebased, #plan))
            local_catch_up(rebased)
            return
          end
          local entry = plan[index]
          local before = entry.headRefOid
          utils.info(string.format("Rebasing #%d (%d/%d)...", entry.number, index, #plan))
          rebase_on_github(repo, entry, function(moved, message)
            if not utils.is_blank(message) then
              utils.info(message)
            end
            if not moved then
              utils.error(string.format("Stopped at #%d: the pull requests above it were left alone", entry.number))
              local_catch_up(rebased)
              return
            end
            if entry.headRefOid ~= before then
              table.insert(
                rebased,
                { number = entry.number, branch = entry.headRefName, before = before, after = entry.headRefOid }
              )
            end
            step(index + 1)
          end)
        end
        step(1)
      end)
    end)
  end

  if number ~= nil then
    run(number)
    return
  end

  -- not in a pull request buffer and no number given: the branch we are on
  utils.get_pull_request_for_current_branch(function(pr)
    if pr == nil or pr.number == nil then
      utils.error "No pull request found for this branch: give a number, as in `Octo stack sync 42`"
      return
    end
    run(pr.number)
  end)
end

---Preview the stack for the current branch and submit it on confirmation.
---Requires the gh-stack extension (gh extension install github/gh-stack).
function M.create()
  gh.stack.view {
    json = true,
    opts = {
      cb = function(output, stderr, exit_code)
        if exit_code ~= 0 then
          if stderr and stderr:find('unknown command "stack"', 1, true) then
            utils.error "The gh-stack extension is required: run 'gh extension install github/gh-stack'"
          elseif exit_code == 2 then
            -- no locally tracked stack: detect stackable open PRs instead,
            -- like GitHub's "This pull request can be stacked" banner
            preview_discovered_stack()
          else
            utils.error(utils.is_blank(stderr) and "Failed to read the stack" or stderr)
          end
          return
        end

        local ok, decoded = pcall(vim.json.decode, output)
        if not ok or utils.is_blank(decoded) or utils.is_blank(decoded.branches) then
          utils.error "Failed to parse the stack"
          return
        end
        local stack = decoded ---@type octo.StackView

        -- The local stack tracks the checked-out branch. When invoked from a
        -- PR buffer whose branch is not part of it, anchor on that PR instead
        -- and discover its chain on GitHub.
        local buffer = utils.get_current_buffer()
        if buffer and buffer:isPullRequest() then
          local head_ref = buffer:pullRequest().headRefName
          local in_local_stack = false
          for _, branch in ipairs(stack.branches) do
            if branch.name == head_ref then
              in_local_stack = true
              break
            end
          end
          if not in_local_stack then
            preview_discovered_stack()
            return
          end
        end

        M.show_stack_preview(stack, function()
          M.submit()
        end)
      end,
    },
  }
end

return M
