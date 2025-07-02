local M = {}

---@class octo.fragments.ProjectsV2Connection
---@field nodes {
---  id: string,
---  project: {
---    id: string,
---    title: string,
---  },
---  fieldValues: {
---    nodes: {
---      name: string,
---      optionId: string,
---      field: {
---        name: string,
---      },
---    }[],
---  },
---}[]

M.projects_v2 = [[
  projectItems(first: 100) {
    nodes {
      id
      project {
        id
        title
      }
      fieldValues(first: 100) {
        nodes {
          ... on ProjectV2ItemFieldSingleSelectValue {
            name
            optionId
            field {
              ... on ProjectV2SingleSelectField {
                name
              }
            }
          }
        }
      }
    }
  }
]]

---@class octo.fragments.Issue
--- @field __typename "Issue"
---@field id string
---@field number integer
---@field title string
---@field state string
---@field stateReason string

M.issue = [[
fragment IssueFields on Issue {
  id
  number
  title
  state
  stateReason
}
]]

---@class octo.fragments.PullRequest
--- @field __typename "PullRequest"
--- @field number integer
--- @field title string
--- @field state string
--- @field isDraft boolean

M.pull_request = [[
fragment PullRequestFields on PullRequest {
  number
  title
  state
  isDraft
}
]]

---@class octo.fragments.ConnectedEvent
--- @field __typename "ConnectedEvent"
--- @field actor { login: string }
--- @field createdAt string
--- @field isCrossRepository boolean
--- @field source octo.fragments.Issue|octo.fragments.PullRequest
--- @field subject octo.fragments.Issue|octo.fragments.PullRequest

M.connected_event = [[
fragment ConnectedEventFragment on ConnectedEvent {
  actor { login }
  createdAt
  isCrossRepository
  source {
    __typename
    ...IssueFields
    ...PullRequestFields
  }
  subject {
    __typename
    ...IssueFields
    ...PullRequestFields
  }
}
]]

---@class octo.fragments.ReferencedEvent
---@field __typename "ReferencedEvent"
---@field createdAt string
---@field actor { login: string }
---@field commit {
---  __typename: string,
---  abbreviatedOid: string,
---  message: string,
---  repository: {
---    nameWithOwner: string,
---  },
---}

M.referenced_event = [[
fragment ReferencedEventFragment on ReferencedEvent {
  createdAt
  actor {
    login
  }
  commit {
    __typename
    abbreviatedOid
    message
    repository {
      nameWithOwner
    }
  }
}
]]
---@class octo.fragments.CrossReferencedEvent
---@field __typename "CrossReferencedEvent"
---@field actor { login: string }
---@field createdAt string
---@field willCloseTarget boolean
---@field source octo.fragments.Issue|octo.fragments.PullRequest
---@field target octo.fragments.Issue|octo.fragments.PullRequest

M.cross_referenced_event = [[
fragment CrossReferencedEventFragment on CrossReferencedEvent {
  createdAt
  actor { login }
  willCloseTarget
  source {
    __typename
    ...IssueFields
    ...PullRequestFields
  }
  target {
    __typename
    ...IssueFields
    ...PullRequestFields
  }
}
]]

---@class octo.fragments.MilestonedEvent
---@field __typename "MilestonedEvent"
---@field actor { login: string }
---@field createdAt string
---@field milestoneTitle string

M.milestoned_event = [[
fragment MilestonedEventFragment on MilestonedEvent {
  actor { login }
  createdAt
  milestoneTitle
}
]]
---@class octo.fragments.DemilestonedEvent
---@field __typename "DemilestonedEvent"
---@field actor { login: string }
---@field createdAt string
---@field milestoneTitle string

M.demilestoned_event = [[
fragment DemilestonedEventFragment on DemilestonedEvent {
  actor { login }
  createdAt
  milestoneTitle
}
]]

---@class octo.ReactionGroupsFragment.reactionGroups
--- @field content string
--- @field viewerHasReacted boolean
--- @field users { totalCount: number }

---@class octo.ReactionGroupsFragment
--- @field reactionGroups octo.ReactionGroupsFragment.reactionGroups[]

M.reaction_groups = [[
fragment ReactionGroupsFragment on Reactable {
  reactionGroups {
    content
    viewerHasReacted
    users {
      totalCount
    }
  }
}
]]
---@class octo.fragments.ReactionGroupsUsers
---@field reactionGroups {
---  content: string,
---  users: {
---    nodes: { login: string }[],
---  },
---}[]

M.reaction_groups_users = [[
fragment ReactionGroupsUsersFragment on Reactable {
  reactionGroups {
    content
    users(last: 100) {
      nodes {
        login
      }
    }
  }
}
]]
---@class octo.fragments.Label
---@field id string
---@field name string
---@field color string

M.label = [[
fragment LabelFragment on Label {
  id
  name
  color
}
]]
---@class octo.fragments.LabelConnection
---@field nodes octo.fragments.Label[]

M.label_connection = [[
fragment LabelConnectionFragment on LabelConnection {
  nodes {
    ...LabelFragment
  }
}
]]
---@class octo.fragments.AssigneeConnection
---@field nodes { id: string, login: string, isViewer: boolean }[]

M.assignee_connection = [[
fragment AssigneeConnectionFragment on UserConnection {
  nodes {
    id
    login
    isViewer
  }
}
]]

---@class octo.fragments.IssueComment : octo.ReactionGroupsFragment
---@field __typename "IssueComment"
---@field id string
---@field body string
---@field createdAt string
---@field author { login: string }
---@field viewerDidAuthor boolean
---@field viewerCanUpdate boolean
---@field viewerCanDelete boolean

M.issue_comment = [[
fragment IssueCommentFragment on IssueComment {
  id
  body
  createdAt
  ...ReactionGroupsFragment
  author {
    login
  }
  viewerDidAuthor
  viewerCanUpdate
  viewerCanDelete
}
]]
---@class octo.fragments.AssignedEvent
---@field __typename "AssignedEvent"
---@field actor { login: string }
---@field assignee { name?: string, login?: string, isViewer?: boolean }
---@field createdAt string

M.assigned_event = [[
fragment AssignedEventFragment on AssignedEvent {
  actor {
    login
  }
  assignee {
    ... on Organization { name }
    ... on Bot { login }
    ... on User {
      login
      isViewer
    }
    ... on Mannequin { login }
  }
  createdAt
}
]]

---@class octo.fragments.LabeledEvent
---@field __typename "LabeledEvent"
---@field actor { login: string }
---@field createdAt string
---@field label octo.fragments.Label

M.labeled_event = [[
fragment LabeledEventFragment on LabeledEvent {
  actor {
    login
  }
  createdAt
  label {
    ...LabelFragment
  }
}
]]

---@class octo.fragments.UnlabeledEvent
---@field __typename "UnlabeledEvent"
---@field actor { login: string }
---@field createdAt string
---@field label octo.fragments.Label

M.unlabeled_event = [[
fragment UnlabeledEventFragment on UnlabeledEvent {
  actor {
    login
  }
  createdAt
  label {
    ...LabelFragment
  }
}
]]
---@class octo.fragments.ClosedEvent
---@field __typename "ClosedEvent"
---@field actor { login: string }
---@field createdAt string
---@field stateReason string
---@field closable { __typename: string, state: string, stateReason?: string }

M.closed_event = [[
fragment ClosedEventFragment on ClosedEvent {
  actor {
    login
  }
  createdAt
  stateReason
  closable {
    __typename
    ... on Issue {
      state
      stateReason
    }
    ... on PullRequest {
      state
    }
  }
}
]]

---@class octo.fragments.ReopenedEvent
---@field __typename "ReopenedEvent"
---@field actor { login: string }
---@field createdAt string

M.reopened_event = [[
fragment ReopenedEventFragment on ReopenedEvent {
  actor {
    login
  }
  createdAt
}
]]
---@class octo.fragments.PullRequestReview.comment : octo.ReactionGroupsFragment
---@field id string
---@field url string
---@field replyTo { id: string, url: string }
---@field body string
---@field commit { oid: string, abbreviatedOid: string }
---@field author { login: string }
---@field authorAssociation string
---@field viewerDidAuthor boolean
---@field viewerCanUpdate boolean
---@field viewerCanDelete boolean
---@field originalPosition integer
---@field position integer
---@field state string
---@field outdated boolean
---@field diffHunk string

---@class octo.fragments.PullRequestReview : octo.ReactionGroupsFragment
---@field __typename "PullRequestReview"
---@field id string
---@field body string
---@field createdAt string
---@field viewerCanUpdate boolean
---@field viewerCanDelete boolean
---@field author { login: string }
---@field viewerDidAuthor boolean
---@field state string
---@field comments {
---  totalCount: integer,
---  nodes: octo.fragments.PullRequestReview.comment[],
---}

M.pull_request_review = [[
fragment PullRequestReviewFragment on PullRequestReview {
  id
  body
  createdAt
  viewerCanUpdate
  viewerCanDelete
  ...ReactionGroupsFragment
  author {
    login
  }
  viewerDidAuthor
  state
  comments(last:100) {
    totalCount
    nodes{
      id
      url
      replyTo { id url }
      body
      commit {
        oid
        abbreviatedOid
      }
      author { login }
      authorAssociation
      viewerDidAuthor
      viewerCanUpdate
      viewerCanDelete
      originalPosition
      position
      state
      outdated
      diffHunk
      ...ReactionGroupsFragment
    }
  }
}
]]
---@class octo.fragments.ProjectCard
---@field id string
---@field note string
---@field state string
---@field column { id: string, name: string }

M.project_cards = [[
fragment ProjectCardFragment on ProjectCard {
  id
  note
  state
  column {
    id
    name
  }
}
]]
---@class octo.fragments.PullRequestCommit
---@field __typename "PullRequestCommit"
---@field commit {
---  messageHeadline: string,
---  committedDate: string,
---  oid: string,
---  abbreviatedOid: string,
---  changedFiles: integer,
---  additions: integer,
---  deletions: integer,
---  author: { user: { login: string } },
---  statusCheckRollup: { state: string },
---  committer: { user: { login: string } },
---}

M.pull_request_commit = [[
fragment PullRequestCommitFragment on PullRequestCommit {
  commit {
    messageHeadline
    committedDate
    oid
    abbreviatedOid
    changedFiles
    additions
    deletions
    author {
      user {
        login
      }
    }
    statusCheckRollup {
      state
    }
    committer {
      user {
        login
      }
    }
  }
}
]]

---@class octo.fragments.ReviewRequestRemovedEvent
---@field __typename "ReviewRequestRemovedEvent"
---@field createdAt string
---@field actor { login: string }
---@field requestedReviewer {
---  login?: string,
---  isViewer?: boolean,
---  name?: string,
---}

M.review_request_removed_event = [[
fragment ReviewRequestRemovedEventFragment on ReviewRequestRemovedEvent {
  createdAt
  actor {
    login
  }
  requestedReviewer {
    ... on User {
      login
      isViewer
    }
    ... on Mannequin {
      login
    }
    ... on Team {
      name
    }
  }
}
]]

---@class octo.fragments.ReviewRequestedEvent
---@field __typename "ReviewRequestedEvent"
---@field createdAt string
---@field actor { login: string }
---@field requestedReviewer {
---  login?: string,
---  isViewer?: boolean,
---  name?: string,
---}

M.review_requested_event = [[
fragment ReviewRequestedEventFragment on ReviewRequestedEvent {
  createdAt
  actor {
    login
  }
  requestedReviewer {
    ... on User {
      login
      isViewer
    }
    ... on Mannequin { login }
    ... on Team { name }
  }
}
]]

---@class octo.fragments.MergedEvent
---@field __typename "MergedEvent"
---@field createdAt string
---@field actor { login: string }
---@field commit { oid: string, abbreviatedOid: string }
---@field mergeRefName string

M.merged_event = [[
fragment MergedEventFragment on MergedEvent {
  createdAt
  actor {
    login
  }
  commit {
    oid
    abbreviatedOid
  }
  mergeRefName
}
]]

---@class octo.fragments.RenamedTitleEvent
---@field __typename "RenamedTitleEvent"
---@field actor { login: string }
---@field createdAt string
---@field previousTitle string
---@field currentTitle string

M.renamed_title_event = [[
fragment RenamedTitleEventFragment on RenamedTitleEvent {
  actor { login }
  createdAt
  previousTitle
  currentTitle
}
]]

---@class octo.fragments.ReviewDismissedEvent
---@field __typename "ReviewDismissedEvent"
---@field createdAt string
---@field actor { login: string }
---@field dismissalMessage string

M.review_dismissed_event = [[
fragment ReviewDismissedEventFragment on ReviewDismissedEvent {
  createdAt
  actor {
    login
  }
  dismissalMessage
}
]]

---@class octo.fragments.PinnedEvent
---@field __typename "PinnedEvent"
---@field actor { login: string }
---@field createdAt string

M.pinned_event = [[
fragment PinnedEventFragment on PinnedEvent {
  actor {
    login
  }
  createdAt
}
]]

---@class octo.fragments.UnpinnedEvent
---@field __typename "UnpinnedEvent"
---@field actor { login: string }
---@field createdAt string

M.unpinned_event = [[
fragment UnpinnedEventFragment on UnpinnedEvent {
  actor {
    login
  }
  createdAt
}
]]

---@class octo.fragments.SubIssueAddedEvent
---@field __typename "SubIssueAddedEvent"
---@field actor { login: string }
---@field createdAt string
---@field subIssue {}

M.subissue_added_event = [[
fragment SubIssueAddedEventFragment on SubIssueAddedEvent {
  actor {
    login
  }
  createdAt
  subIssue {
    ...IssueFields
  }
}
]]

---@class octo.fragments.SubIssueRemovedEvent
---@field __typename "SubIssueRemovedEvent"
---@field actor { login: string }
---@field createdAt string
---@field subIssue {}

M.subissue_removed_event = [[
fragment SubIssueRemovedEventFragment on SubIssueRemovedEvent {
  actor {
    login
  }
  createdAt
  subIssue {
    ...IssueFields
  }
}
]]

---@class octo.fragments.ParentIssueAddedEvent
---@field __typename "ParentIssueAddedEvent"
---@field actor { login: string }
---@field createdAt string
---@field parent {}

M.parent_issue_added_event = [[
fragment ParentIssueAddedEventFragment on ParentIssueAddedEvent {
  actor {
    login
  }
  createdAt
  parent {
    ...IssueFields
  }
}
]]

---@class octo.fragments.ParentIssueRemovedEvent
---@field __typename "ParentIssueRemovedEvent"
---@field actor { login: string }
---@field createdAt string
---@field parent {}

M.parent_issue_removed_event = [[
fragment ParentIssueRemovedEventFragment on ParentIssueRemovedEvent {
  actor {
    login
  }
  createdAt
  parent {
    ...IssueFields
  }
}
]]
---@class octo.fragments.IssueTypeAddedEvent
---@field __typename "IssueTypeAddedEvent"
---@field actor { login: string }
---@field createdAt string
---@field issueType { id: string, name: string, color: string }

M.issue_type_added_event = [[
fragment IssueTypeAddedEventFragment on IssueTypeAddedEvent {
  actor {
    login
  }
  createdAt
  issueType {
    id
    name
    color
  }
}
]]
---@class octo.fragments.IssueTypeRemovedEvent
---@field __typename "IssueTypeRemovedEvent"
---@field actor { login: string }
---@field createdAt string
---@field issueType { id: string, name: string, color: string }

M.issue_type_removed_event = [[
fragment IssueTypeRemovedEventFragment on IssueTypeRemovedEvent {
  actor {
    login
  }
  createdAt
  issueType {
    id
    name
    color
  }
}
]]
---@class octo.fragments.IssueTypeChangedEvent
---@field __typename "IssueTypeChangedEvent"
---@field actor { login: string }
---@field createdAt string
---@field prevIssueType { id: string, name: string, color: string }
---@field issueType { id: string, name: string, color: string }

M.issue_type_changed_event = [[
fragment IssueTypeChangedEventFragment on IssueTypeChangedEvent {
  actor {
    login
  }
  createdAt
  prevIssueType {
    id
    name
    color
  }
  issueType {
    id
    name
    color
  }
}
]]
---@alias octo.IssueTimelineItem octo.fragments.AssignedEvent|octo.fragments.ClosedEvent|octo.fragments.ConnectedEvent|octo.fragments.ReferencedEvent|octo.fragments.CrossReferencedEvent|octo.fragments.DemilestonedEvent|octo.fragments.IssueComment|octo.fragments.LabeledEvent|octo.fragments.MilestonedEvent|octo.fragments.RenamedTitleEvent|octo.fragments.ReopenedEvent|octo.fragments.UnlabeledEvent|octo.fragments.PinnedEvent|octo.fragments.UnpinnedEvent|octo.fragments.SubIssueAddedEvent|octo.fragments.SubIssueRemovedEvent|octo.fragments.ParentIssueAddedEvent|octo.fragments.ParentIssueRemovedEvent|octo.fragments.IssueTypeAddedEvent|octo.fragments.IssueTypeRemovedEvent|octo.fragments.IssueTypeChangedEvent

---@class octo.fragments.IssueTimelineItemsConnection
---@field nodes octo.IssueTimelineItem[]

M.issue_timeline_items_connection = [[
fragment IssueTimelineItemsConnectionFragment on IssueTimelineItemsConnection {
  nodes {
    __typename
    ...AssignedEventFragment
    ...ClosedEventFragment
    ...ConnectedEventFragment
    ...ReferencedEventFragment
    ...CrossReferencedEventFragment
    ...DemilestonedEventFragment
    ...IssueCommentFragment
    ...LabeledEventFragment
    ...MilestonedEventFragment
    ...RenamedTitleEventFragment
    ...ReopenedEventFragment
    ...UnlabeledEventFragment
    ...PinnedEventFragment
    ...UnpinnedEventFragment
    ...SubIssueAddedEventFragment
    ...SubIssueRemovedEventFragment
    ...ParentIssueAddedEventFragment
    ...ParentIssueRemovedEventFragment
    ...IssueTypeAddedEventFragment
    ...IssueTypeRemovedEventFragment
    ...IssueTypeChangedEventFragment
  }
}
]]
---@alias octo.PullRequestTimelineItem octo.fragments.AssignedEvent|octo.fragments.ClosedEvent|octo.fragments.ConnectedEvent|octo.fragments.CrossReferencedEvent|octo.fragments.DemilestonedEvent|octo.fragments.IssueComment|octo.fragments.LabeledEvent|octo.fragments.MergedEvent|octo.fragments.MilestonedEvent|octo.fragments.PullRequestCommit|octo.fragments.PullRequestReview|octo.fragments.RenamedTitleEvent|octo.fragments.ReopenedEvent|octo.fragments.ReviewDismissedEvent|octo.fragments.ReviewRequestRemovedEvent|octo.fragments.ReviewRequestedEvent|octo.fragments.UnlabeledEvent

---@class octo.fragments.PullRequestTimelineItemsConnection
---@field nodes octo.PullRequestTimelineItem[]

M.pull_request_timeline_items_connection = [[
fragment PullRequestTimelineItemsConnectionFragment on PullRequestTimelineItemsConnection {
  nodes {
    __typename
    ...AssignedEventFragment
    ...ClosedEventFragment
    ...ConnectedEventFragment
    ...CrossReferencedEventFragment
    ...DemilestonedEventFragment
    ...IssueCommentFragment
    ...LabeledEventFragment
    ...MergedEventFragment
    ...MilestonedEventFragment
    ...PullRequestCommitFragment
    ...PullRequestReviewFragment
    ...RenamedTitleEventFragment
    ...ReopenedEventFragment
    ...ReviewDismissedEventFragment
    ...ReviewRequestRemovedEventFragment
    ...ReviewRequestedEventFragment
    ...UnlabeledEventFragment
  }
}
]]
---@class octo.fragments.IssueInformation
---@field id string
---@field number integer
---@field state string
---@field stateReason string
---@field issueType { id: string, name: string, color: string }
---@field title string
---@field body string
---@field createdAt string
---@field closedAt string
---@field updatedAt string
---@field url string
---@field viewerDidAuthor boolean
---@field viewerCanUpdate boolean
---@field milestone { title: string, state: string }
---@field author { login: string }

M.issue_information = [[
fragment IssueInformationFragment on Issue {
  id
  number
  state
  stateReason
  issueType {
    id
    name
    color
  }
  title
  body
  createdAt
  closedAt
  updatedAt
  url
  viewerDidAuthor
  viewerCanUpdate
  milestone {
    title
    state
  }
  author {
    login
  }
}
]]

---@class octo.ReviewThreadCommentFragment : octo.ReactionGroupsFragment
--- @field id string
--- @field body string
--- @field diffHunk string
--- @field createdAt string
--- @field lastEditedAt string
--- @field outdated boolean
--- @field originalCommit { oid: string, abbreviatedOid: string }
--- @field author { login: string }
--- @field authorAssociation string
--- @field viewerDidAuthor boolean
--- @field viewerCanUpdate boolean
--- @field viewerCanDelete boolean
--- @field state string
--- @field url string
--- @field replyTo { id: string, url: string }
--- @field pullRequestReview { id: string, state: string }
--- @field path string

M.review_thread_comment = [[
fragment ReviewThreadCommentFragment on PullRequestReviewComment {
  id
  body
  diffHunk
  createdAt
  lastEditedAt
  outdated
  originalCommit {
    oid
    abbreviatedOid
  }
  author {
    login
  }
  authorAssociation
  viewerDidAuthor
  viewerCanUpdate
  viewerCanDelete
  state
  url
  replyTo {
    id
    url
  }
  pullRequestReview {
    id
    state
  }
  path
  ...ReactionGroupsFragment
}
]]

---@class octo.ReviewThreadInformationFragment
--- @field id string
--- @field path string
--- @field diffSide string
--- @field startDiffSide string
--- @field line number
--- @field originalLine number
--- @field startLine number
--- @field originalStartLine number
--- @field resolvedBy { login: string }
--- @field isResolved boolean
--- @field isCollapsed boolean
--- @field isOutdated boolean

M.review_thread_information = [[
fragment ReviewThreadInformationFragment on PullRequestReviewThread {
  id
  path
  diffSide
  startDiffSide
  line
  originalLine
  startLine
  originalStartLine
  resolvedBy {
    login
  }
  isResolved
  isCollapsed
  isOutdated
}
]]

---@class octo.fragments.DiscussionInfo
---@field id string
---@field number integer
---@field title string
---@field url string
---@field closed boolean
---@field isAnswered boolean
---@field viewerDidAuthor boolean
---@field repository { nameWithOwner: string }
---@field author { login: string }

M.discussion_info = [[
fragment DiscussionInfoFragment on Discussion {
  id
  number
  title
  url
  closed
  isAnswered
  viewerDidAuthor
  repository {
    nameWithOwner
  }
  author {
    login
  }
}
]]
---@class octo.fragments.DiscussionDetails : octo.fragments.DiscussionInfo, octo.ReactionGroupsFragment
---@field body string
---@field category { name: string, emoji: string }
---@field answer { author: { login: string }, body: string, createdAt: string, viewerDidAuthor: boolean }
---@field createdAt string
---@field closedAt string
---@field updatedAt string
---@field upvoteCount integer
---@field viewerHasUpvoted boolean
---@field viewerDidAuthor boolean

M.discussion_details = [[
fragment DiscussionDetailsFragment on Discussion {
  ...DiscussionInfoFragment
  body
  category {
    name
    emoji
  }
  answer {
    author {
      login
    }
    body
    createdAt
    viewerDidAuthor
  }
  createdAt
  closedAt
  updatedAt
  upvoteCount
  viewerHasUpvoted
  viewerDidAuthor
  ...ReactionGroupsFragment
}
]]
---@class octo.fragments.DiscussionComment : octo.ReactionGroupsFragment
---@field __typename string
---@field id string
---@field body string
---@field url string
---@field createdAt string
---@field lastEditedAt string
---@field author { login: string }
---@field replyTo { id: string }
---@field viewerDidAuthor boolean
---@field viewerCanUpdate boolean
---@field viewerCanDelete boolean

M.discussion_comment = [[
fragment DiscussionCommentFragment on DiscussionComment {
  __typename
  id
  body
  url
  createdAt
  lastEditedAt
  ...ReactionGroupsFragment
  author {
    login
  }
  replyTo {
    id
  }
  viewerDidAuthor
  viewerCanUpdate
  viewerCanDelete
}
]]
---@class octo.fragments.Repository
---@field id string
---@field createdAt string
---@field description string
---@field diskUsage integer
---@field forkCount integer
---@field isArchived boolean
---@field isDisabled boolean
---@field isEmpty boolean
---@field isFork boolean
---@field isInOrganization boolean
---@field isPrivate boolean
---@field isSecurityPolicyEnabled boolean
---@field name string
---@field nameWithOwner string
---@field parent { nameWithOwner: string }
---@field stargazerCount integer
---@field updatedAt string
---@field url string

M.repository = [[
fragment RepositoryFragment on Repository {
  id
  createdAt
  description
  diskUsage
  forkCount
  isArchived
  isDisabled
  isEmpty
  isFork
  isInOrganization
  isPrivate
  isSecurityPolicyEnabled
  name
  nameWithOwner
  parent {
    nameWithOwner
  }
  stargazerCount
  updatedAt
  url
}
]]

return M
