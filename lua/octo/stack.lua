local gh = require "octo.gh"
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
    table.insert(lines, " ⚠ some branches need a rebase: run 'gh stack sync' first")
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
