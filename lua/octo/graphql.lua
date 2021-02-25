local M = {}

-- https://docs.github.com/en/free-pro-team@latest/graphql/reference/mutations#resolvereviewthread
M.resolve_review_mutation =
  [[
  mutation {
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
  mutation {
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
  mutation {
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
  mutation {
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
            id
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
  mutation {
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
            id
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
  mutation {
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
            id
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
          isCollapsed
          isOutdated
          path
          resolvedBy { login }
          line
          originalLine
          startLine
          originalStartLine
          diffSide
          comments(first: 100, after: $endCursor) {
            nodes{
              id
              body
              createdAt
              commit {
                oid
              }
              replyTo { id }
              author { login }
              authorAssociation
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
      reviewThreads(last:100) {
        nodes {
          id
          isResolved
          isCollapsed
          isOutdated
          path
          resolvedBy { login }
          line
          originalLine
          startLine
          originalStartLine
          diffSide
          comments(first: 100) {
            nodes{
              id
              body
              createdAt
              replyTo { id }
              commit {
                oid
              }
              author { login }
              authorAssociation
              outdated
              diffHunk
              reactions(last:20) {
                totalCount
                nodes{
                  content
                }
              }
            }
          }
        }
      }
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
          comments(last:100) {
            totalCount
            nodes{
              id
              replyTo {
                id
              }
              body
              commit {
                oid
              }
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
  user(login: "%s") {
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
  organization(login: "%s") {
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

-- https://docs.github.com/en/graphql/reference/mutations#addprojectcard
M.add_project_card_mutation =
  [[
  mutation {
    addProjectCard(input: {contentId: "%s", projectColumnId: "%s"}) {
      cardEdge {
        node {
          id
        }
      }
    }
  }
]]

-- https://docs.github.com/en/graphql/reference/mutations#moveprojectcard
M.move_project_card_mutation =
  [[
  mutation {
    moveProjectCard(input: {cardId: "%s", columnId: "%s"}) {
      cardEdge {
        node {
          id
        }
      }
    }
  }
]]

-- https://docs.github.com/en/graphql/reference/mutations#deleteprojectcard
M.delete_project_card_mutation =
  [[
  mutation {
    deleteProjectCard(input: {cardId: "%s"}) {
      deletedCardId
    }
  }
]]

-- https://docs.github.com/en/graphql/reference/mutations#removelabelsfromlabelable
M.add_labels_mutation =
  [[
  mutation {
    addLabelsToLabelable(input: {labelableId: "%s", labelIds: ["%s"]}) {
      labelable {
        ... on Issue {
          id
        }
        ... on PullRequest {
          id
        }
      }
    }
  }
]]

-- https://docs.github.com/en/graphql/reference/mutations#removelabelsfromlabelable
M.remove_labels_mutation =
  [[
  mutation {
    removeLabelsFromLabelable(input: {labelableId: "%s", labelIds: ["%s"]}) {
      labelable {
        ... on Issue {
          id
        }
        ... on PullRequest {
          id
        }
      }
    }
  }
]]

-- https://docs.github.com/en/graphql/reference/objects#label
M.labels_query =
  [[
  query {
    repository(owner: "%s", name: "%s") {
      labels(first: 100) {
        nodes {
          id
          name
          color
        }
      }
    }
  }
]]

M.issue_labels_query =
  [[
  query {
    repository(owner: "%s", name: "%s") {
      issue(number: %d) {
        labels(first: 100) {
          nodes {
            id
            name
            color
          }
        }
      }
    }
  }
]]

M.pull_request_labels_query =
  [[
  query {
    repository(owner: "%s", name: "%s") {
      pullRequest(number: %d) {
        labels(first: 100) {
          nodes {
            id
            name
            color
          }
        }
      }
    }
  }
]]

-- https://docs.github.com/en/graphql/reference/mutations#createlabel
-- requires application/vnd.github.bane-preview+json
M.create_label_mutation =
  [[
  mutation {
    createLabel(input: {repositoryId: "%s", name: "%s", description: "%s", color: "%s") {
      label {
        id
        name
      }
    }
  }
]]

M.issue_assignees_query =
  [[
  query {
    repository(owner: "%s", name: "%s") {
      issue(number: %d) {
        assignees(first: 100) {
          nodes {
            id
            login
          }
        }
      }
    }
  }
]]

M.pull_request_assignees_query =
  [[
  query {
    repository(owner: "%s", name: "%s") {
      pullRequest(number: %d) {
        assignees(first: 100) {
          nodes {
            id
            login
          }
        }
      }
    }
  }
]]

-- https://docs.github.com/en/graphql/reference/mutations#addassigneestoassignable
M.add_assignees_mutation =
  [[
  mutation {
    addAssigneesToAssignable(input: {assignableId: "%s", assigneeIds: ["%s"]}) {
      assignable {
        ... on Issue {
          id
        }
        ... on PullRequest {
          id
        }
      }
    }
  }
]]

-- https://docs.github.com/en/graphql/reference/mutations#removeassigneestoassignable
M.remove_assignees_mutation =
  [[
  mutation {
    removeAssigneesFromAssignable(input: {assignableId: "%s", assigneeIds: ["%s"]}) {
      assignable {
        ... on Issue {
          id
        }
        ... on PullRequest {
          id
        }
      }
    }
  }
]]

-- https://docs.github.com/en/graphql/reference/mutations#requestreviews
-- for teams use `teamIds`
M.request_reviews_mutation =
  [[
  mutation {
    requestReviews(input: {pullRequestId: "%s", userIds: ["%s"]}) {
      pullRequest {
        id
      }
    }
  }
]]

M.user_query =
  [[
query($endCursor: String) {
  search(query: "%s", type: USER, first: 100) {
    nodes {
      ... on User {
        id
        login
      }
      ... on Organization {
        id
        login
        teams(first:100, after: $endCursor) {
          totalCount
          nodes {
            id
            name
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
]]

M.changed_files_query =
  [[
query($endCursor: String) {
  repository(owner: "%s", name: "%s") {
    pullRequest(number: %d) {
      files(first:100, after: $endCursor) {
        nodes {
          additions
          deletions
          path
        }
        pageInfo {
          hasNextPage
          endCursor
        }
      }
    }
  }
}
]]

M.file_content_query =
  [[
query {
  repository(owner: "%s", name: "%s") {
    object(expression: "%s:%s") {
      ... on Blob {
        text
      }
    }
  }
}
]]

return M
