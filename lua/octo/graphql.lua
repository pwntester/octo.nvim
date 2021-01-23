local M = {}

-- https://docs.github.com/en/free-pro-team@latest/graphql/reference/mutations#resolvereviewthread
M.resolve_review_mutation =
  [[
  mutation ResolveReview {
    resolveReviewThread(input: {threadId: "%s"}) {
      thread {
        isResolved
      }
    }
  }
]]

-- https://docs.github.com/en/free-pro-team@latest/graphql/reference/mutations#unresolvereviewthread
M.unresolve_review_mutation =
  [[
  mutation UnresolveReview {
    unresolveReviewThread(input: {threadId: "%s"}) {
      thread {
        isResolved
      }
    }
  }
]]

-- https://docs.github.com/en/graphql/reference/mutations#addpullrequestreview
M.submit_review_mutation =
  [[
  mutation AddPullRequestReview {
    addPullRequestReview(input: {pullRequestId: "%s", event: %s, body: "%s", threads: [%s] }) {
      pullRequestReview {
        id
        state
      }
    }
  }
]]

-- https://docs.github.com/en/free-pro-team@latest/graphql/reference/mutations#createissue
M.create_issue_mutation =
  [[
  mutation CreateIssue {
    createIssue(input: {repositoryId: "%s", title: "%s", body: "%s"}) {
      issue {
        id
        number
        state
        title
        body
        createdAt
        closedAt
        updatedAt
        url
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
        reactions(last: 20) {
          totalCount
          nodes {
            content
          }
        }
        comments(first: 100) {
          nodes {
            id
            body
            createdAt
            reactions(last:20) {
              totalCount
              nodes {
                content
              }
            }
            author {
              login
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
            login
          }
        }
      }
    }
  }
]]

-- https://docs.github.com/en/free-pro-team@latest/graphql/reference/mutations#updateissue
M.update_issue_state_mutation =
  [[
  mutation UpdateIssue {
    updateIssue(input: {id: "%s", state: %s}) {
      issue {
        id
        number
        state
        title
        body
        createdAt
        closedAt
        updatedAt
        url
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
        reactions(last: 20) {
          totalCount
          nodes {
            content
          }
        }
        comments(first: 100) {
          nodes {
            id
            body
            createdAt
            reactions(last:20) {
              totalCount
              nodes {
                content
              }
            }
            author {
              login
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
            login
          }
        }
      }
    }
  }
]]

-- https://docs.github.com/en/free-pro-team@latest/graphql/reference/mutations#updatepullrequest
M.update_pull_request_state_mutation =
  [[
  mutation UpdatePullRequest {
    updatePullRequest(input: {pullRequestId: "%s", state: %s}) {
      pullRequest {
        id
        number
        state
        title
        body
        createdAt
        closedAt
        updatedAt
        url
        merged
        mergedBy {
          login
        }
        participants(first:10) {
          nodes {
            login
          }
        }
        additions
        deletions
        commits {
          totalCount
        }
        changedFiles
        headRefName
        headRefOid
        baseRefName
        baseRefOid
        baseRepository {
          nameWithOwner
        }
        milestone {
          title
          state
        }
        author {
          login
        }
        reactions(last: 20) {
          totalCount
          nodes {
            content
          }
        }
        comments(first: 100) {
          nodes {
            id
            body
            createdAt
            reactions(last:20) {
              totalCount
              nodes {
                content
              }
            }
            author {
              login
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
            login
          }
        }
        reviewRequests(first: 20) {
          totalCount
          nodes {
            requestedReviewer {
              ... on User {
                login
              }
              ... on Team {
                name
              }
            }
          }
        }
      }
    }
  }
]]

-- https://docs.github.com/en/free-pro-team@latest/graphql/reference/objects#pullrequestreviewthread
M.review_threads_query =
  [[
query($endCursor: String) {
  repository(owner:"%s", name:"%s") {
    pullRequest(number:%d) {
        reviewThreads(last:80) {
          nodes {
            id
            isResolved
            isOutdated
            path
            resolvedBy { login }
            line
            originalLine
            startLine
            originalStartLine
            comments(first: 100, after: $endCursor) {
              nodes{
                id
                body
                author { login }
                authorAssociation
                originalPosition
                position
                state
                outdated
                diffHunk
                reactions(last:20) {
                  totalCount
                  nodes{
                    content
                  }
                }
              }
              pageInfo {
                hasNextPage
                endCursor
              }
            }
          }
      }
    }
  }
}
]]

-- https://docs.github.com/en/free-pro-team@latest/graphql/reference/objects#pullrequest
M.pull_request_query =
  [[
query($endCursor: String) {
  repository(owner: "%s", name: "%s") {
    pullRequest(number: %d) {
      id
      number
      state
      title
      body
      createdAt
      closedAt
      updatedAt
      url
      merged
      mergedBy {
        login
      }
      participants(first:10) {
        nodes {
          login
        }
      }
      additions
      deletions
      commits {
        totalCount
      }
      changedFiles
      headRefName
      headRefOid
      baseRefName
      baseRefOid
      baseRepository {
        nameWithOwner
      }
      milestone {
        title
        state
      }
      author {
        login
      }
      reactions(last: 20) {
        totalCount
        nodes {
          content
        }
      }
      comments(first: 100, after: $endCursor) {
        nodes {
          id
          body
          createdAt
          reactions(last:20) {
            totalCount
            nodes {
              content
            }
          }
          author {
            login
          }
        }
        pageInfo {
          hasNextPage
          endCursor
        }
      }
      reviewDecision
      reviews(last:100) {
        nodes {
          id
          body
          createdAt
          reactions(last:20) {
            totalCount
            nodes {
              content
            }
          }
          author {
            login
          }
          state
          comments {
            totalCount
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
          login
        }
      }
      reviewRequests(first: 20) {
        totalCount
        nodes {
          requestedReviewer {
            ... on User {
              login
            }
            ... on Team {
              name
            }
          }
        }
      }
    }
  }
}
]]

-- https://docs.github.com/en/free-pro-team@latest/graphql/reference/objects#issue
M.issue_query =
  [[
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
      reactions(last: 20) {
        totalCount
        nodes {
          content
        }
      }
      projectCards(last: 20) {
        nodes {
          state
          column {
            name
          }
          project {
            name
          }
        }
      }
      comments(first: 100, after: $endCursor) {
        nodes {
          id
          body
          createdAt
          reactions(last:20) {
            totalCount
            nodes {
              content
            }
          }
          author {
            login
          }
        }
        pageInfo {
          hasNextPage
          endCursor
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
          login
        }
      }
    }
  }
}
]]

-- https://docs.github.com/en/free-pro-team@latest/graphql/reference/objects#repository
M.repository_id_query = [[
query {
  repository(owner: "%s", name: "%s") {
    id
  }
}
]]

-- https://docs.github.com/en/free-pro-team@latest/graphql/reference/objects#issue
-- https://docs.github.com/en/free-pro-team@latest/graphql/reference/input-objects#issueorder
-- https://docs.github.com/en/free-pro-team@latest/graphql/reference/input-objects#issuefilters
-- filter eg: labels: ["help wanted", "bug"]
M.issues_query =
  [[
query($endCursor: String) {
  repository(owner: "%s", name: "%s") {
    issues(first: 100, after: $endCursor, filterBy: {%s}) {
      nodes {
        number
        title
      }
      pageInfo {
        hasNextPage
        endCursor
      }
    }
  }
}
]]
M.pull_requests_query =
  [[
query($endCursor: String) {
  repository(owner: "%s", name: "%s") {
    pullRequests(first: 100, after: $endCursor, %s) {
      nodes {
        number
        title
      }
      pageInfo {
        hasNextPage
        endCursor
      }
    }
  }
}
]]

M.search_pull_requests_query =
  [[
query {
  search(query: "repo:%s is:pr %s", type: ISSUE, last: 100) {
    nodes {
      ... on PullRequest {
        number
        title
      }
    }
  }
}
]]

M.search_issues_query =
  [[
query {
  search(query: "repo:%s is:issue %s", type: ISSUE, last: 100) {
    nodes {
      ... on Issue{
        number
        title
      }
    }
  }
}
]]

-- https://docs.github.com/en/graphql/reference/objects#project
M.projects_query =
[[
query {
  repository(owner: "%s", name: "%s") {
    projects(first: 100) {
      nodes {
        id 
        name
        columns(first:100) {
          nodes {
            id
            name
          }
        }
      }
    }
  }
}
]]

return M
