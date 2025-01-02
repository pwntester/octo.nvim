local M = {}

M.projects_v2_fragment = [[
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
M.reaction_groups_fragment = [[
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
M.reaction_groups_users_fragment = [[
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
M.label_fragment = [[
fragment LabelFragment on Label {
  id
  name
  color
}
]]
M.label_connection_fragment = [[
fragment LabelConnectionFragment on LabelConnection {
  nodes {
    ...LabelFragment
  }
}
]]
M.assignee_connection_fragment = [[
fragment AssigneeConnectionFragment on UserConnection {
  nodes {
    id
    login
    isViewer
  }
}
]]

M.issue_comment_fragment = [[
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

return M
