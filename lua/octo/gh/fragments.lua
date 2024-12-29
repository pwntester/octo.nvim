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

return M
