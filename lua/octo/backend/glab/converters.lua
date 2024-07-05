local cli = require "octo.backend.glab.cli"
local constants = require "octo.constants"
local utils = require "octo.utils"
local date = require "octo.date"

---@alias glab_user { id: string, name: string, username: string }
---@alias gh_user { id: string, login: string, username: string, isViewer: boolean }
---@alias glab_label { id: string?, title: string, color: string}
---@alias gh_label { id: string?, name: string, color: string}

--- gh reviewThreads graphql
---@class gh_thread
---@field id string
---@field isResolved boolean
---@field isCollapsed boolean
---@field isOutdated boolean
---@field path string
---@field resolvedBy { login: string }
---@field line number?
---@field originalLine number?
---@field startLine number? multiline only
---@field originalStartLine number? multiline only
---@field diffSide "LEFT"|"RIGHT
---@field startDiffSide string? multiline only
---@field comments { nodes: gh_thread_comment[] }

---@class gh_thread_comment
---@field id string
---@field body string
---@field createdAt string
---@field lastEditedAt string?
---@field updatedAt string?
---@field url string?
---@field replyTo { url: string}? Thread header nil, else set
---@field state "PENDING"|"COMMENTED"
---@field originalCommit { oid: string, abbreviatedOid: string }?
---@field pullRequestReview { id: string, state: string }?
---@field path string?
---@field author { login: string }
---@field viewerDidAuthor boolean?
---@field viewerCanUpdate boolean?
---@field viewerCanDelete boolean?
---@field outdated boolean?
---@field diffHunk string?

---@class glab_discussion
---@field id string
---@field individual_note boolean
---@field notes glab_note[]
--
---@class glab_note
---@field id string
---@field type string? DIFFNOTE or nil
---@field note string? pending_note
---@field body string? committed_note
---@field author glab_user? committed_note
---@field created_at string? committed_note
---@field updated_at string? committed_note
---@field system boolean? committed_note, review thread or automatic
---@field noteable_id number? committed_note
---@field noteable_iid number? committed_note
---@field position glab_position? only if thread_header
---@field discussion_id number?
---@field author_id number
---@field commit_id string?
---@field merge_request_id number
---@field line_code string
---@field resolvable boolean
---@field resolved boolean? commited diff note
---@field resolved_by glab_user? commited diff note
---@field resolve_discussion boolean? pending_note
---@field state string? pending_note injected

---@class glab_position
---@field base_sha string -- SHA of base commit of source_branch
---@field start_sha string -- SHA of target_branch
---@field head_sha string -- SHA of source_branch
---@field position_type string "text"
---@field old_line number?
---@field new_line number?
---@field old_path string
---@field new_path string
---@field line_range { start: glab_line_code, end: glab_line_code }

---@class glab_line_code
---@field line_code string
---@field type string
---@field old_line number?
---@field new_line number?

---@class glab_diff
---@field diff string diff-style or unified
---@field new_path string
---@field old_path string
---@field a_mode string
---@field b_mode string
---@field new_file boolean
---@field renamed_file boolean
---@field deleted_file boolean
---@field generated_file any

---@class glab_commit
---@field id string
---@field short_id string
---@field created_at string
---@field parent_ids string[]
---@field title string
---@field message string
---@field author_name string
---@field author_email string
---@field authored_date string

---@class gh_commit
---@field sha string
---@field parents { sha: string }[]
---@field commit { message: string, author: { name: string, email: string, date: string }}

---@class glab_rest_pr REST
---@field id number global_id
---@field iid number
---@field title string
---@field source_branch string
---@field web_url string

---@class gh_pr
---@field __typename string
---@field number number
---@field global_id number? only, if it was converted from a glab_rest_pr
---@field title string
---@field headRefName string
---@field repository { nameWithOwner: string } "owner/name"
---@field url string

---@class glab_graphql_pr
---@field id number global_id
---@field iid number
---@field state string
---@field approved boolean
---@field author glab_user
---@field reviewers { nodes: glab_user[] }
---@field assignees { nodes: glab_user[] }
---@field participants { nodes: glab_user[] }
---@field title string
---@field description string
---@field sourceBranch string
---@field targetBranch string
---@field createdAt string
---@field mergedAt string
---@field updatedAt string
---@field commitCount number
---@field labels { nodes: glab_label[] }
---@field diffStats { path: string }
---@field diffStatsSummary { additions: number, changes: number, deletions: number, fileCount: number }
---@field diffRefs { baseSha: string, headSha: string, startSha: string }
---@field webUrl string

---@class gh_minimal_pr
---@field __typename string
---@field id number iid
---@field number number iid
---@field global_id number? only, if it was converted from a glab_rest_pr
---@field title string
---@field body string
---@field state string
---@field reviewDecision string
---@field author gh_user
---@field assignees { nodes: gh_user[] }
---@field reviewRequests { nodes: { requestedReviewer: gh_user[]}, totalCount: integer}
---@field participants { nodes: gh_user[]}
---@field createdAt string
---@field closedAt string
---@field updatedAt string
---@field viewerDidAuthor boolean
---@field labels { nodes: gh_label[]}
---@field files { nodes: { path: string , viewerViewedState: boolean}[]}
---@field additions number
---@field changes number
---@field deletions number
---@field changedFiles number
---@field commits { totalCount: number }
---@field headRefName string
---@field baseRefName string
---@field baseRefOid string
---@field headRefOid string
---@field url string
---@field timelineItems { nodes: table } dummy
---@field reviewThreads { nodes: table} dummy

local M = {}

---@param state string
---@return string
local function convert_issue_state(state)
  if state == "opened" then
    return "open"
  else
    return state
  end
end

---@param is_approved boolean
---@return string
local function convert_issue_approved(is_approved)
  if is_approved then
    return "APPROVED"
  else
    return "REVIEW_REQUIRED"
  end
end

---@param diffStats { path: string}[]
---@return { nodes: { path: string , viewerViewedState: boolean}[]}
local function convert_issue_filelist(diffStats)
  ---@type { nodes: { path: string , viewerViewedState: boolean}[]}
  local converted_filelist = { ["nodes"] = {} }
  for i, diffStat in ipairs(diffStats) do
    converted_filelist.nodes[i] = { ["path"] = diffStat.path, ["viewerViewedState"] = false }
  end
  return converted_filelist
end

---@param user glab_user
---@return gh_user
local function convert_user(user)
  ---@type gh_user
  return {
    ["id"] = user.id,
    ["login"] = user.name,
    ["username"] = user.username,
    ["isViewer"] = cli.get_user_name() == user.username,
  }
end

---@param users glab_user[]
---@return { nodes: gh_user[]}
local function convert_users(users)
  ---@type { nodes: gh_user[]}
  local converted_users = { ["nodes"] = {} }
  for i, user in ipairs(users) do
    converted_users.nodes[i] = convert_user(user)
  end
  return converted_users
end

---@param reviewers { nodes: glab_user[]}
---@return { nodes: { requestedReviewer: gh_user[]}, totalCount: integer}
local function convert_reviewers(reviewers)
  ---@type { nodes: { requestedReviewer: gh_user[]}, totalCount: integer}
  local converted_reviewers = { ["nodes"] = {} }
  local count = 0
  for i, user in ipairs(reviewers.nodes) do
    converted_reviewers.nodes[i] = { ["requestedReviewer"] = convert_user(user) }
    count = count + 1
  end
  converted_reviewers.totalCount = count
  return converted_reviewers
end

---@param labels { nodes: glab_label[]}
---@return { nodes: gh_label[]}
function M.convert_labels(labels)
  ---@type { nodes: gh_label[]}
  local converted_labels = { ["nodes"] = {} }
  for i, label in ipairs(labels.nodes) do
    converted_labels.nodes[i] = {
      ["id"] = label.id,
      ["name"] = label.title,
      ["color"] = label.color,
    }
  end
  return converted_labels
end

---@param diff glab_diff
---@return string
function M.convert_file_status(diff)
  if diff.new_file then
    return "A"
  elseif diff.renamed_file then
    return "R"
  elseif diff.deleted_file then
    return "D"
  else
    return "M"
  end
end

---APPROVE COMMENT DISMISS REQUEST_CHANGES
---anything besides those needs no extra cmd
---@param event string
---@return string
function M.convert_event_to_glab_cmd(event)
  if event == "APPROVE" then
    return "approve"
  elseif event == "REQUEST_CHANGES" then
    return "revoke"
  end
  return event
end

---Used by initial fzf finder PR list for minimal output
---maybe no need to have an extra function for that
---@param pull_requests glab_rest_pr[]
---@param repo string
---@return gh_pr[]?, integer?
function M.parse_merge_requests_output(pull_requests, repo)
  if #pull_requests == 0 then
    utils.error(string.format("There are no matching pull requests in %s.", repo))
    return
  end

  local owner, name = utils.split_repo(repo)

  local max_number = -1
  for _, pull in ipairs(pull_requests) do
    if #tostring(pull.iid) > max_number then
      max_number = #tostring(pull.iid)
    end
  end

  local converted_pull_requests = {}
  for i, pull_request in pairs(pull_requests) do
    converted_pull_requests[i] = {
      ["__typename"] = "PullRequest",
      ["title"] = pull_request.title,
      ["number"] = pull_request.iid,
      ["global_id"] = pull_request.id,
      ["headRefName"] = pull_request.source_branch,
      ["repository"] = { ["nameWithOwner"] = string.format("%s/%s", owner, name) },
      ["url"] = pull_request.web_url,
    }
  end

  return converted_pull_requests, max_number
end

---@param pr glab_graphql_pr
---@return gh_minimal_pr
function M.convert_graphql_pull_request(pr)
  ---@type gh_minimal_pr
  return {
    ["__typename"] = "PullRequest",
    ["id"] = pr.iid,
    ["number"] = pr.iid,
    ["global_id"] = pr.id, -- 254887887
    ["title"] = pr.title,
    ["body"] = pr.description,
    ["state"] = convert_issue_state(pr.state),
    ["reviewDecision"] = convert_issue_approved(pr.approved),
    ["author"] = convert_user(pr.author),
    ["assignees"] = convert_users(pr.assignees.nodes),
    ["reviewRequests"] = convert_reviewers(pr.reviewers),
    ["participants"] = convert_users(pr.participants.nodes),
    ["createdAt"] = pr.createdAt,
    ["closedAt"] = pr.mergedAt,
    ["updatedAt"] = pr.updatedAt,
    ["viewerDidAuthor"] = cli.get_user_name() == pr.author.username,
    ["labels"] = M.convert_labels(pr.labels),
    ["files"] = convert_issue_filelist(pr.diffStats),
    ["additions"] = pr.diffStatsSummary.additions,
    ["changes"] = pr.diffStatsSummary.changes,
    ["deletions"] = pr.diffStatsSummary.deletions,
    ["changedFiles"] = pr.diffStatsSummary.fileCount,
    ["commits"] = { ["totalCount"] = pr.commitCount },
    ["headRefName"] = pr.sourceBranch,
    ["baseRefName"] = pr.targetBranch,
    ["baseRefOid"] = pr.diffRefs.baseSha,
    ["headRefOid"] = pr.diffRefs.headSha,
    ["url"] = pr.webUrl,
    -- This is done separately, since graphql discussions share way too little
    ["timelineItems"] = { ["nodes"] = {} },
    ["reviewThreads"] = { ["nodes"] = {} },
  }
end

---Converts a single pending note to a thread comment
---@param note glab_note
---@param author gh_user
---@return gh_thread_comment
function M.convert_pending_note_to_thread_comment(note, author)
  local now = date(os.time())
  ---@type gh_thread_comment
  return {
    ["id"] = note.id,
    ["body"] = note.note,
    ["author"] = author,
    ["type"] = "DiffNote",
    ["state"] = "PENDING",
    ["createdAt"] = now,
    ["updatedAt"] = now,
    ["resolved"] = false,
    ["position"] = note.position,
  }
end

-- #233 MISSING: ReviewRequestRemovedEvent
---Converts a single discussion
---@param discussion glab_discussion
---@param own_name string
---@return table refer to gh graphql pull_request_query
local function convert_discussion_to_thread(discussion, own_name)
  local thread_header = discussion.notes[1]

  local thread = { ["createdAt"] = thread_header.created_at }
  local author = { ["login"] = thread_header.author.name, ["username"] = thread_header.author.username }

  if thread_header.type == "DiffNote" then
    thread.__typename = "PullRequestReview"
    thread.id = discussion.id
    thread.author = author
    thread.viewerDidAuthor = thread_header.author.username == own_name
    thread.state = thread_header.state or "COMMENTED"
    thread.viewerCanUpdate = true
    thread.viewerCanDelete = true

    local comments = {}
    local count_comments = 0
    for _, note in pairs(discussion.notes) do
      count_comments = count_comments + 1
      table.insert(comments, {
        ["id"] = note.id,
        ["url"] = "google.com",
        ["body"] = note.body,
        -- doesnt seem to have any effect
        --["commit"] = { ["oid"] = note.position.start_sha, ["abbreviatedOid"] = string.sub(note.position.start_sha, 1, 7) },
        ["author"] = { ["login"] = note.author.name, ["username"] = note.author.username },
        ["createdAt"] = note.created_at,
        ["lastEditedAt"] = note.updated_at,
        ["authorAssociation"] = "OWNER",
        ["viewerDidAuthor"] = note.author.username == own_name,
        ["viewerCanUpdate"] = true,
        ["viewerCanDelete"] = true,
        ["outdated"] = false,
        ["state"] = note.state or "SUBMITTED",
      })
    end
    thread.comments = { ["nodes"] = comments, ["totalCount"] = count_comments }
  elseif not thread_header.system then
    -- #233 IssueComment's can be replied to with glab!
    -- Implement an iteration of the notes, but beforehand
    -- need to add this functionality within octo-buffer I suppose
    thread.__typename = "IssueComment"
    thread.author = author
    thread.body = thread_header.body
    thread.viewerDidAuthor = thread_header.author.name == own_name
  elseif string.find(thread_header.body, "assigned to") then
    local assignee = string.match(thread_header.body, constants.ASSIGN_EVENT_PATTERN)
    thread.__typename = "AssignedEvent"
    thread.actor = author
    thread.assignee = { ["login"] = assignee, ["isViewer"] = own_name == assignee }
  elseif string.find(thread_header.body, "added") then
    local count_commits, commits = string.match(thread_header.body, constants.PULL_REQUEST_COMMIT_EVENT_PATTERN)
    local commit_hash, commit_msg, rest = string.match(commits, constants.PULL_REQUEST_COMMIT_PATTERN)
    -- #234 This dumps "added the following 42 commits" into one line, when rebasing an old branch.
    -- But single events for each commit would probably be even worse?
    -- Relatively common occurence.
    local temp_msg
    while rest do
      _, temp_msg, rest = string.match(rest, constants.PULL_REQUEST_COMMIT_PATTERN)
      if temp_msg then
        commit_msg = commit_msg .. "||" .. temp_msg
      end
    end
    thread.__typename = "PullRequestCommit"
    thread.commit = {
      ["abbreviatedOid"] = string.sub(commit_hash, 1, 7),
      ["messageHeadline"] = commit_msg,
      ["committer"] = { ["user"] = author },
    }
  elseif string.find(thread_header.body, "requested review from") then
    local requestedReviewer = string.match(thread_header.body, constants.REQUEST_REVIEW_EVENT_PATTERN)
    thread.__typename = "ReviewRequestedEvent"
    thread.actor = author
    thread.requestedReviewer = {
      ["login"] = requestedReviewer,
      ["username"] = requestedReviewer,
      ["isViewer"] = requestedReviewer == own_name,
    }
  end

  return thread
end

---transforms discussions to threads
---@param discussions glab_discussion[]
---@param own_name string
---@return table
function M.convert_discussions_to_threads(discussions, own_name)
  local threads = { ["nodes"] = {} }

  for i, discussion in ipairs(discussions) do
    threads.nodes[i] = convert_discussion_to_thread(discussion, own_name)
  end

  return threads
end

---@param note glab_note
---@param own_name string
---@param relevant_diffs string
---@param thread_id string
---@return gh_thread_comment
function M.convert_note_to_reviewthread(note, own_name, relevant_diffs, thread_id)
  local original_commit
  -- the SHA is only available if the note is the thread header
  if note.position.head_sha ~= vim.NIL then
    original_commit = {
      ["oid"] = note.position.head_sha,
      ["abbreviatedOid"] = string.sub(note.position.head_sha, 1, 7),
    }
  end
  ---@type gh_thread_comment
  return {
    ["id"] = note.id,
    ["body"] = note.body,
    ["diffHunk"] = relevant_diffs,
    ["path"] = note.position.new_path,
    ["createdAt"] = note.created_at,
    ["updatedAt"] = note.updated_at,
    ["lastEditedAt"] = note.updated_at,
    ["originalCommit"] = original_commit,
    ["author"] = { ["login"] = note.author.name, ["username"] = note.author.username },
    ["authorAssociation"] = "OWNER", -- #233 I deeply dont care about that
    ["viewerDidAuthor"] = note.author.username == own_name,
    ["viewerCanUpdate"] = true,
    ["viewerCanDelete"] = true,
    ["state"] = note.state or "COMMENTED",
    ["url"] = "not a thing.#233", -- #233 I deeply dont care about that
    ["replyTo"] = { ["url"] = "not a thing.#233" }, -- #233 I deeply dont care about that
    ["pullRequestReview"] = {
      ["id"] = thread_id,
      ["state"] = note.state or "COMMENTED",
    },
  }
end

---@param discussion glab_discussion
---@param own_name string
---@return gh_thread
function M.convert_discussion_to_reviewthreads(discussion, own_name)
  local thread_header = discussion.notes[1]
  local diffside
  local line

  if thread_header.position.old_line ~= vim.NIL then
    diffside = "LEFT"
    line = thread_header.position.old_line
  else
    diffside = "RIGHT"
    line = thread_header.position.new_line
  end

  local start_sha = thread_header.position.start_sha
  local head_sha = thread_header.position.head_sha
  -- #234 need to inject the diff of a thread in a clever manner
  -- Cannot be based upon the MR Diff since the thread is bound to a certain SHA
  -- Current version: use `git diff` locally
  --  -> sadly bombs if we didnt fetch beforehand / the sha is not available
  -- Alternative: `/projects/:id/repository/files/:file_path/raw?ref=:commit_hash`
  --  -> Fetch file content for [old|new]_path with [start|head]_hash, then diff -u?
  --  -> Lots of requests, and probably need to create temporary files?
  local diff = utils.get_diff_between_commits(start_sha, head_sha)
  local diffhunks = utils.extract_diffhunks_from_diff(diff)
  local relevant_diffs = diffhunks[thread_header.position.new_path]

  ---@type gh_thread_comment[]
  local comments = {}
  for _, note in pairs(discussion.notes) do
    local converted_note = M.convert_note_to_reviewthread(note, own_name, relevant_diffs, discussion.id)
    table.insert(comments, converted_note)
  end
  -- Thread header has to have no replyTo to render correctly,
  -- but thread comments got to have one!
  comments[1].replyTo = nil

  local resolved_by
  if thread_header.resolved then
    resolved_by = { ["login"] = thread_header.resolved_by.username }
  end

  ---@type gh_thread
  return {
    ["id"] = discussion.id,
    ["path"] = thread_header.position.new_path,
    ["line"] = line,
    ["originalLine"] = line,
    ["startLine"] = line,
    --["originalStartLine"] = thread_header.old_line, --multiline only,
    ["isResolved"] = thread_header.resolved,
    ["resolvedBy"] = resolved_by,
    ["isCollapsed"] = thread_header.resolved,
    ["isOutdated"] = false,
    ["diffSide"] = diffside,
    --["startDiffSide"] = diffside, --multiline only,
    ["comments"] = {
      ["nodes"] = comments,
    },
  }
end

---@param commits glab_commit[]
---@return gh_commit[]
function M.convert_commits(commits)
  ---@type gh_commit[]
  local converted_commits = {}
  for i, commit in ipairs(commits) do
    converted_commits[i] = {
      ["sha"] = commit.id,
      ["parents"] = { [1] = { ["sha"] = "not implemented" } }, -- wouldnt know how to get with glab
      ["commit"] = {
        ["message"] = commit.message,
        ["author"] = {
          ["name"] = commit.author_name,
          ["email"] = commit.author_email,
          ["date"] = commit.authored_date,
        },
      },
    }
  end
  return converted_commits
end

return M
