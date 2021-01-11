local M = {}

-- https://docs.github.com/en/free-pro-team@latest/graphql/reference/mutations#resolvereviewthread
M.resolve_review_mutation = [[
  mutation ResolveReview {
    resolveReviewThread(input: {threadId: "%s"}) {
      thread {
        isResolved
      }
    }
  }
]]

-- https://docs.github.com/en/free-pro-team@latest/graphql/reference/mutations#unresolvereviewthread
M.unresolve_review_mutation = [[
  mutation UnresolveReview {
    unresolveReviewThread(input: {threadId: "%s"}) {
      thread {
        isResolved
      }
    }
  }
]]

-- https://docs.github.com/en/free-pro-team@latest/graphql/reference/objects#pullrequestreviewthread
M.review_threads_query = [[
query($endCursor: String) {
  repository(owner:"%s", name:"%s") {
    pullRequest(number:%d){
        reviewThreads(last:80) {
          nodes{
            id
            isResolved
            isOutdated
            path
            line
            resolvedBy { login }
            originalLine
            startLine
            originalStartLine
            comments(first: 100, after: $endCursor) {
              nodes{
                id
                body
                author { login }
                authorAssociation
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
M.pull_query = [[
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
      additions
      deletions
      commits {
        totalCount
      }
      changedFiles
      headRefName
      baseRefName
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
      labels(first: 20) {
        nodes {
          color
          name
        }
      }
      assignees(first: 20) {
        nodes {
          id
        }
      }
      reviewRequests(first: 20) {
        totalCount
        nodes {
          requestedReviewer {
            ... on User {
              login
            }
            ... on User {
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
      labels(first: 20) {
        nodes {
          color
          name
        }
      }
      assignees(first: 20) {
        nodes {
          id
        }
      }
    }
  }
}
]]

return M
