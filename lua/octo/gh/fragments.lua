local M = {}

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

M.issue = [[
fragment IssueFields on Issue {
  number
  title
  state
  stateReason
}
]]
M.pull_request = [[
fragment PullRequestFields on PullRequest {
  number
  title
  state
  isDraft
}
]]
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
M.milestoned_event = [[
fragment MilestonedEventFragment on MilestonedEvent {
  actor { login }
  createdAt
  milestoneTitle
}
]]
M.demilestoned_event = [[
fragment DemilestonedEventFragment on DemilestonedEvent {
  actor { login }
  createdAt
  milestoneTitle
}
]]
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
M.label = [[
fragment LabelFragment on Label {
  id
  name
  color
}
]]
M.label_connection = [[
fragment LabelConnectionFragment on LabelConnection {
  nodes {
    ...LabelFragment
  }
}
]]
M.assignee_connection = [[
fragment AssigneeConnectionFragment on UserConnection {
  nodes {
    id
    login
    isViewer
  }
}
]]

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

M.closed_event = [[
fragment ClosedEventFragment on ClosedEvent {
  actor {
    login
  }
  createdAt
}
]]

M.reopened_event = [[
fragment ReopenedEventFragment on ReopenedEvent {
  actor {
    login
  }
  createdAt
}
]]

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

M.renamed_title_event = [[
fragment RenamedTitleEventFragment on RenamedTitleEvent {
  actor { login }
  createdAt
  previousTitle
  currentTitle
}
]]

M.review_dismissed_event = [[
fragment ReviewDismissedEventFragment on ReviewDismissedEvent {
  createdAt
  actor {
    login
  }
  dismissalMessage
}
]]

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
  }
}
]]

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

M.issue_information = [[
fragment IssueInformationFragment on Issue {
  id
  number
  state
  stateReason
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

M.discussion_info = [[
fragment DiscussionInfoFragment on Discussion {
  id
  number
  title
  url
  closed
  isAnswered
  repository {
    nameWithOwner
  }
  author {
    login
  }
}
]]

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
  ...ReactionGroupsFragment
}
]]

M.discussion_comment = [[
fragment DiscussionCommentFragment on DiscussionComment {
  id
  body
  createdAt
  lastEditedAt
  ...ReactionGroupsFragment
  author {
    login
  }
  viewerDidAuthor
  viewerCanUpdate
  viewerCanDelete
}
]]

return M
