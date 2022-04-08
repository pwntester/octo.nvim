local M = {}

-- https://docs.github.com/en/free-pro-team@latest/graphql/reference/objects#issue
M.issue_query = [[
query($endCursor: String) {
  repository(owner: "%s", name: "%s") {
    issue(number: %d) {
      id
      number
      state
      title
      body
      createdAt
      closedAt
      updatedAt
      url
      viewerDidAuthor
      viewerCanUpdate
      repository {
        nameWithOwner
      }
      milestone {
        title
        state
      }
      author {
        login
      }
      participants(first:10) {
        nodes {
          login
        }
      }
      reactionGroups {
        content
        viewerHasReacted
        users {
          totalCount
        }
      }
      projectCards(last: 20) {
        nodes {
          id
          state
          column {
            name
          }
          project {
            name
          }
        }
      }
      timelineItems(first: 100, after: $endCursor) {
        pageInfo {
          hasNextPage
          endCursor
        }
        nodes {
          __typename
          ... on LabeledEvent {
            actor {
              login
            }
            createdAt
            label {
              color
              name
            }
          }
          ... on UnlabeledEvent {
            actor {
              login
            }
            createdAt
            label {
              color
              name
            }
          }
          ... on IssueComment {
            id
            body
            createdAt
            reactionGroups {
              content
              viewerHasReacted
              users {
                totalCount
              }
            }
            author {
              login
            }
            viewerDidAuthor
            viewerCanUpdate
            viewerCanDelete
          }
          ... on ClosedEvent {
            createdAt
            actor {
              login
            }
          }
          ... on ReopenedEvent {
            createdAt
            actor {
              login
            }
          }
          ... on AssignedEvent {
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
        }
      }
      labels(first: 20) {
        nodes {
          color
          name
        }
      }
      assignees(first: 20) {
        nodes {
          id
          login
          isViewer
        }
      }
    }
  }
}
]]

-- https://docs.github.com/en/free-pro-team@latest/graphql/reference/objects#issue
-- https://docs.github.com/en/free-pro-team@latest/graphql/reference/input-objects#issueorder
-- https://docs.github.com/en/free-pro-team@latest/graphql/reference/input-objects#issuefilters
-- filter eg: labels: ["help wanted", "bug"]
M.issues_query = [[
query($endCursor: String) {
  repository(owner: "%s", name: "%s") {
    issues(first: 100, after: $endCursor, filterBy: {%s}) {
      nodes {
        __typename
        number
        title
        url
        repository { nameWithOwner }
      }
      pageInfo {
        hasNextPage
        endCursor
      }
    }
  }
}
]]

local function escape_chars(str)
  local escaped, _ = string.gsub(str, '["\\]', {
    ['"'] = '\\"',
    ["\\"] = "\\\\",
  })
  return escaped
end

local I = {}

function I.g(query, ...)
  local opts = { escape = true }
  for _, v in ipairs { ... } do
    if type(v) == "table" then
      opts = vim.tbl_deep_extend("force", opts, v)
      break
    end
  end
  local escaped = {}
  for _, v in ipairs { ... } do
    if type(v) == "string" and opts.escape then
      local encoded = escape_chars(v)
      table.insert(escaped, encoded)
    else
      table.insert(escaped, v)
    end
  end
  return string.format(M[query], unpack(escaped))
end

return I
