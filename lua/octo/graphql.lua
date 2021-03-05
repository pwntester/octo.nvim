local M = {}

-- https://docs.github.com/en/graphql/reference/mutations#addreaction
M.add_reaction_mutation =
  [[
  mutation {
    addReaction(input: {subjectId: "%s", content: %s}) {
      subject {
        reactionGroups {
          content
          users {
            totalCount
          }
        }
      }
    }
  }
]]

-- https://docs.github.com/en/graphql/reference/mutations#removereaction
M.remove_reaction_mutation =
  [[
  mutation {
    removeReaction(input: {subjectId: "%s", content: %s}) {
      subject {
        reactionGroups {
          content
          users {
            totalCount
          }
        }
      }
    }
  }
]]

-- https://docs.github.com/en/free-pro-team@latest/graphql/reference/mutations#resolvereviewthread
M.resolve_review_thread_mutation =
  [[
  mutation {
    resolveReviewThread(input: {threadId: "%s"}) {
      thread {
        originalStartLine
        originalLine
        isOutdated
        isResolved
        path
      }
    }
  }
]]

-- https://docs.github.com/en/free-pro-team@latest/graphql/reference/mutations#unresolvereviewthread
M.unresolve_review_thread_mutation =
  [[
  mutation {
    unresolveReviewThread(input: {threadId: "%s"}) {
      thread {
        originalStartLine
        originalLine
        isOutdated
        isResolved
        path
      }
    }
  }
]]

-- https://docs.github.com/en/graphql/reference/mutations#addpullrequestreview
M.start_review_mutation =
  [[
  mutation {
    addPullRequestReview(input: {pullRequestId: "%s"}) {
      pullRequestReview {
        id
        state
      }
    }
  }
]]

-- https://docs.github.com/en/graphql/reference/mutations#addpullrequestreview
M.submit_pull_request_review_mutation =
  [[
  mutation {
    submitPullRequestReview(input: {pullRequestReviewId: "%s", event: %s, body: "%s"}) {
      pullRequestReview {
        id
        state
      }
    }
  }
]]

M.delete_pull_request_review_mutation =
[[
mutation { 
  deletePullRequestReview(input: {pullRequestReviewId: "%s"}) { 
    pullRequestReview {
      id
    }
  }
}
]]

-- https://docs.github.com/en/graphql/reference/mutations#addpullrequestreviewthread
M.add_pull_request_review_thread_mutation =
[[
mutation { 
  addPullRequestReviewThread(input: { pullRequestReviewId: "%s", body: "%s", path: "%s", side: %s, line:%d}) { 
    thread {
      path
      diffSide
      startDiffSide
      line
      startLine
      comments(first:1) {
        nodes {
          id
          body
          diffHunk
          commit { abbreviatedOid }
          pullRequestReview {
            id
          }
        }
      }
    }
  }
}
]]

-- https://docs.github.com/en/graphql/reference/mutations#addpullrequestreviewthread
M.add_pull_request_review_multiline_thread_mutation =
[[
mutation { 
  addPullRequestReviewThread(input: { pullRequestReviewId: "%s", body: "%s", path: "%s", startSide: %s, side: %s, startLine: %d, line:%d}) { 
    thread {
      path
      diffSide
      startDiffSide
      line
      startLine
      comments(first:1) {
        nodes {
          id
          body
          diffHunk
          commit { abbreviatedOid }
          pullRequestReview {
            id
          }
        }
      }
    }
  }
}
]]

-- https://docs.github.com/en/graphql/reference/mutations#addcomment
M.add_issue_comment_mutation =
[[
  mutation {
    addComment(input: {subjectId: "%s", body: "%s"}) {
      commentEdge {
        node {
          id
          body
        }
      }
    }
  }
]]

-- https://docs.github.com/en/graphql/reference/mutations#updateissuecomment
M.update_issue_comment_mutation =
[[
  mutation {
    updateIssueComment(input: {id: "%s", body: "%s"}) {
      issueComment {
        id
        body
      }
    }
  }
]]

-- https://docs.github.com/en/graphql/reference/mutations#updatepullrequestreviewcomment
M.update_pull_request_review_comment_mutation =
[[
  mutation {
    updatePullRequestReviewComment(input: {pullRequestReviewCommentId: "%s", body: "%s"}) {
      pullRequestReviewComment {
        id
        body
      }
    }
  }
]]

-- https://docs.github.com/en/graphql/reference/mutations#updatepullrequestreview
M.update_pull_request_review_mutation =
[[
  mutation {
    updatePullRequestReview(input: {pullRequestReviewId: "%s", body: "%s"}) {
      pullRequestReview {
        id
        body
      }
    }
  }
]]

-- https://docs.github.com/en/graphql/reference/mutations#addpullrequestreviewcomment
-- M.add_pull_request_review_comment_mutation =
-- [[
--   mutation {
--     addPullRequestReviewComment(input: {inReplyTo: "%s", body: "%s"}) {
--       comment{
--         id
--         body
--       }
--     }
--   }
-- ]]

-- M.add_pull_request_review_comment_mutation =
-- [[
--   mutation {
--     addPullRequestReviewThreadReply(input: { pullRequestReviewThreadId: "%s", body: "%s"}) {
--       comment{
--         id
--         body
--       }
--     }
--   }
-- ]]

-- https://docs.github.com/en/graphql/reference/mutations#deleteissuecomment
M.delete_issue_comment_mutation =
  [[
  mutation {
    deleteIssueComment(input: {id: "%s"}) {
      clientMutationId
    }
  }
]]

-- https://docs.github.com/en/graphql/reference/mutations#deletepullrequestreviewcomment
M.delete_pull_request_review_comment_mutation =
  [[
  mutation {
    deletePullRequestReviewComment(input: {id: "%s"}) {
      clientMutationId
    }
  }
]]

-- https://docs.github.com/en/free-pro-team@latest/graphql/reference/mutations#updateissue
M.update_issue_mutation =
  [[
  mutation {
    updateIssue(input: {id: "%s", title: "%s", body: "%s"}) {
      issue {
        id
        number
        state
        title
        body
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
        reactionGroups {
          content
          users {
            totalCount
          }
        }
        comments(first: 100) {
          nodes {
            id
            body
            createdAt
            reactionGroups {
              content
              users {
                totalCount
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
M.update_issue_mutation =
  [[
  mutation {
    updateIssue(input: {id: "%s", title: "%s", body: "%s"}) {
      issue {
        id
        number
        state
        title
        body
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
        reactionGroups {
          content
          users {
            totalCount
          }
        }
        comments(first: 100) {
          nodes {
            id
            body
            createdAt
            reactionGroups {
              content
              users {
                totalCount
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
M.update_pull_request_mutation =
  [[
  mutation {
    updatePullRequest(input: {pullRequestId: "%s", title: "%s", body: "%s"}) {
      pullRequest {
        id
        number
        state
        title
        body
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
        reactionGroups {
          content
          users {
            totalCount
          }
        }
        comments(first: 100) {
          nodes {
            id
            body
            createdAt
            reactionGroups {
              content
              users {
                totalCount
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

-- https://docs.github.com/en/free-pro-team@latest/graphql/reference/mutations#unresolvereviewthread
M.pending_review_threads_query =
[[
query { 
  repository(owner:"%s", name:"%s") {
    pullRequest (number: %d){
      reviews(first:1, states:PENDING) {
        nodes {
          id
        }
      }
      reviewThreads(last:50) {
        nodes {	
          path
          diffSide
          startDiffSide
          line
          startLine
          comments(first:1) {
            nodes {
              id
              body
              diffHunk
              commit { abbreviatedOid }
              pullRequestReview {
                id
              }
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
              state
              commit {
                oid
              }
              replyTo { id }
              author { login }
              authorAssociation
              outdated
              diffHunk
              reactionGroups {
                content
                users {
                  totalCount
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
      reactionGroups {
        content
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
          ... on AssignedEvent {
            assignee {
              ... on User {
                login
              }
            }
            createdAt
          }
          ... on PullRequestCommit {
            commit {
              committedDate
              abbreviatedOid
              changedFiles
              additions
              deletions
              committer {
                user {
                  login
                }
              }
            }          
          }
          ... on MergedEvent {
            createdAt
            actor {
              login
            }
            commit {
              abbreviatedOid
            }
            mergeRefName
          }
          ... on ClosedEvent {
            createdAt
            actor {
              login
            }
          }
          ... on IssueComment {
            id
            body
            createdAt
            reactionGroups {
              content
              users {
                totalCount
              }
            }
            author {
              login
            }
          }
          ... on PullRequestReview {
            id
            body
            createdAt
            reactionGroups {
              content
              users {
                totalCount
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
                reactionGroups {
                  content
                  users {
                    totalCount
                  }
                }
              }
            }
          }
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
              state
              commit {
                oid
              }
              author { login }
              authorAssociation
              outdated
              diffHunk
              reactionGroups {
                content
                users {
                  totalCount
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
      reactionGroups {
        content
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
          ... on IssueComment {
            id
            body
            createdAt
            reactionGroups {
              content
              users {
                totalCount
              }
            }
            author {
              login
            }
          }
          ... on ClosedEvent {
            createdAt
            actor {
              login
            }
          }
          ... on AssignedEvent {
            assignee {
              ... on User {
                login
              }
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

local function escape_chars(string)
  local escaped, _ = string.gsub(
    string,
    '["]',
    {
      ['"'] = '\\"',
    }
  )
  return escaped
end

return function(query, ...)
  local opts = { escape = true }
  for _, v in ipairs{...} do
    if type(v) == "table" then
      opts = v
      break
    end
  end
  local escaped = {}
  for _, v in ipairs{...} do
    if type(v) == "string" and opts.escape then
      local encoded = escape_chars(v)
      table.insert(escaped, encoded)
    else
      table.insert(escaped, v)
    end
  end
  return string.format(M[query], unpack(escaped))
end

