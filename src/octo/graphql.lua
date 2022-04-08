local M = {}

-- https://docs.github.com/en/graphql/reference/mutations#addreaction
M.add_reaction_mutation = [[
  mutation {
    addReaction(input: {subjectId: "%s", content: %s}) {
      subject {
        reactionGroups {
          content
          viewerHasReacted
          users {
            totalCount
          }
        }
      }
    }
  }
]]

-- https://docs.github.com/en/graphql/reference/mutations#removereaction
M.remove_reaction_mutation = [[
  mutation {
    removeReaction(input: {subjectId: "%s", content: %s}) {
      subject {
        reactionGroups {
          content
          viewerHasReacted
          users {
            totalCount
          }
        }
      }
    }
  }
]]

-- https://docs.github.com/en/free-pro-team@latest/graphql/reference/mutations#resolvereviewthread
M.resolve_review_thread_mutation = [[
  mutation {
    resolveReviewThread(input: {threadId: "%s"}) {
      thread {
        originalStartLine
        originalLine
        isOutdated
        isResolved
        path
        pullRequest {
          reviewThreads(last:100) {
            nodes {	
              id
              path
              diffSide
              startDiffSide
              line
              originalLine
              startLine
              originalStartLine
              isResolved
              isCollapsed
              isOutdated
              comments(first:100) {
                nodes {
                  id
                  body
                  diffHunk
                  createdAt
                  lastEditedAt
                  commit { abbreviatedOid }
                  author {login}
                  authorAssociation
                  viewerDidAuthor
                  viewerCanUpdate
                  viewerCanDelete
                  state
                  replyTo { id }
                  pullRequestReview {
                    id
                    state
                  }
                  path
                  reactionGroups {
                    content
                    viewerHasReacted
                    users {
                      totalCount
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
]]

-- https://docs.github.com/en/free-pro-team@latest/graphql/reference/mutations#unresolvereviewthread
M.unresolve_review_thread_mutation = [[
  mutation {
    unresolveReviewThread(input: {threadId: "%s"}) {
      thread {
        originalStartLine
        originalLine
        isOutdated
        isResolved
        path
        pullRequest {
          reviewThreads(last:100) {
            nodes {	
              id
              path
              diffSide
              startDiffSide
              line
              originalLine
              startLine
              originalStartLine
              isResolved
              isCollapsed
              isOutdated
              comments(first:100) {
                nodes {
                  id
                  body
                  diffHunk
                  commit { abbreviatedOid }
                  createdAt
                  lastEditedAt
                  author {login}
                  authorAssociation
                  viewerDidAuthor
                  viewerCanUpdate
                  viewerCanDelete
                  state
                  replyTo { id }
                  pullRequestReview {
                    id
                    state
                  }
                  path
                  reactionGroups {
                    content
                    viewerHasReacted
                    users {
                      totalCount
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
]]

-- https://docs.github.com/en/graphql/reference/mutations#addpullrequestreview
M.start_review_mutation = [[
  mutation {
    addPullRequestReview(input: {pullRequestId: "%s"}) {
      pullRequestReview {
        id
        state
        pullRequest {
          reviewThreads(last:100) {
            nodes {	
              id
              path
              line
              originalLine
              startLine
              originalStartLine
              diffSide
              startDiffSide
              isResolved
              isCollapsed
              isOutdated
              comments(first:100) {
                nodes {
                  id
                  body
                  diffHunk
                  createdAt
                  lastEditedAt
                  commit { abbreviatedOid }
                  author {login}
                  authorAssociation
                  viewerDidAuthor
                  viewerCanUpdate
                  viewerCanDelete
                  state
                  replyTo { id }
                  pullRequestReview {
                    id
                    state
                  }
                  path
                  reactionGroups {
                    content
                    viewerHasReacted
                    users {
                      totalCount
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
]]

-- https://docs.github.com/en/graphql/reference/mutations#markfileasviewed
M.mark_file_as_viewed_mutation = [[
  mutation {
    markFileAsViewed(input: {path: "%s", pullRequestId: "%s"}) {
      pullRequest {
        files(first:100){
          nodes {
            path
            viewerViewedState
          }
        }
      }
    }
  }
]]

-- https://docs.github.com/en/graphql/reference/mutations#unmarkfileasviewed
M.unmark_file_as_viewed_mutation = [[
  mutation {
    unmarkFileAsViewed(input: {path: "%s", pullRequestId: "%s"}) {
      pullRequest {
        files(first:100){
          nodes {
            path
            viewerViewedState
          }
        }
      }
    }
  }
]]

-- https://docs.github.com/en/graphql/reference/mutations#addpullrequestreview
M.submit_pull_request_review_mutation = [[
  mutation {
    submitPullRequestReview(input: {pullRequestReviewId: "%s", event: %s, body: "%s"}) {
      pullRequestReview {
        id
        state
      }
    }
  }
]]

M.delete_pull_request_review_mutation = [[
mutation { 
  deletePullRequestReview(input: {pullRequestReviewId: "%s"}) { 
    pullRequestReview {
      id
      state
    }
  }
}
]]

-- https://docs.github.com/en/graphql/reference/mutations#addpullrequestreviewthread
M.add_pull_request_review_thread_mutation = [[
mutation { 
  addPullRequestReviewThread(input: { pullRequestReviewId: "%s", body: "%s", path: "%s", side: %s, line:%d}) { 
    thread {
      id
      comments(last:100) {
        nodes {
          id
          body
          diffHunk
          createdAt
          lastEditedAt
          commit { abbreviatedOid }
          author {login}
          authorAssociation
          viewerDidAuthor
          viewerCanUpdate
          viewerCanDelete
          state
          replyTo { id }
          pullRequestReview {
            id
            state
          }
          path
          reactionGroups {
            content
            viewerHasReacted
            users {
              totalCount
            }
          }
        } 
      }
      pullRequest {
        reviewThreads(last:100) {
          nodes {	
            id
            path
            diffSide
            startDiffSide
            line
            originalLine
            startLine
            originalStartLine
            isResolved
            isCollapsed
            isOutdated
            comments(first:100) {
              nodes {
                id
                body
                diffHunk
                createdAt
                lastEditedAt
                commit { abbreviatedOid }
                author {login}
                authorAssociation
                viewerDidAuthor
                viewerCanUpdate
                viewerCanDelete
                state
                replyTo { id }
                pullRequestReview {
                  id
                  state
                }
                path
                reactionGroups {
                  content
                  viewerHasReacted
                  users {
                    totalCount
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
]]

-- https://docs.github.com/en/graphql/reference/mutations#addpullrequestreviewthread
M.add_pull_request_review_multiline_thread_mutation = [[
mutation { 
  addPullRequestReviewThread(input: { pullRequestReviewId: "%s", body: "%s", path: "%s", startSide: %s, side: %s, startLine: %d, line:%d}) { 
    thread {
      id
      comments(last:100) {
        nodes {
          id
          body
          diffHunk
          createdAt
          lastEditedAt
          commit { abbreviatedOid }
          author {login}
          authorAssociation
          viewerDidAuthor
          viewerCanUpdate
          viewerCanDelete
          state
          replyTo { id }
          pullRequestReview {
            id
            state
          }
          path
          reactionGroups {
            content
            viewerHasReacted
            users {
              totalCount
            }
          }
        } 
      }
      pullRequest {
        reviewThreads(last:100) {
          nodes {	
            id
            path
            diffSide
            startDiffSide
            line
            originalLine
            startLine
            originalStartLine
            isResolved
            isCollapsed
            isOutdated
            comments(first:100) {
              nodes {
                id
                body
                diffHunk
                createdAt
                lastEditedAt
                commit { abbreviatedOid }
                author {login}
                authorAssociation
                viewerDidAuthor
                viewerCanUpdate
                viewerCanDelete
                state
                replyTo { id }
                pullRequestReview {
                  id
                  state
                }
                path
                reactionGroups {
                  content
                  viewerHasReacted
                  users {
                    totalCount
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
]]

-- https://docs.github.com/en/graphql/reference/mutations#addcomment
M.add_issue_comment_mutation = [[
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
M.update_issue_comment_mutation = [[
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
M.update_pull_request_review_comment_mutation = [[
  mutation {
    updatePullRequestReviewComment(input: {pullRequestReviewCommentId: "%s", body: "%s"}) {
      pullRequestReviewComment {
        id
        body
        pullRequest {
          reviewThreads(last:100) {
            nodes {	
              id
              path
              diffSide
              startDiffSide
              line
              originalLine
              startLine
              originalStartLine
              isResolved
              isCollapsed
              isOutdated
              comments(first:100) {
                nodes {
                  id
                  body
                  diffHunk
                  createdAt
                  lastEditedAt
                  commit { abbreviatedOid }
                  author {login}
                  authorAssociation
                  viewerDidAuthor
                  viewerCanUpdate
                  viewerCanDelete
                  state
                  replyTo { id }
                  pullRequestReview {
                    id
                    state
                  }
                  path
                  reactionGroups {
                    content
                    viewerHasReacted
                    users {
                      totalCount
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
]]

-- https://docs.github.com/en/graphql/reference/mutations#updatepullrequestreview
M.update_pull_request_review_mutation = [[
  mutation {
    updatePullRequestReview(input: {pullRequestReviewId: "%s", body: "%s"}) {
      pullRequestReview {
        id
        state
        body
      }
    }
  }
]]

-- https://docs.github.com/en/graphql/reference/mutations#addpullrequestreviewcomment
M.add_pull_request_review_comment_mutation = [[
  mutation {
    addPullRequestReviewComment(input: {inReplyTo: "%s", body: "%s", pullRequestReviewId: "%s"}) {
      comment {
        id
        body
        pullRequest {
          reviewThreads(last:100) {
            nodes {	
              id
              path
              diffSide
              startDiffSide
              line
              originalLine
              startLine
              originalStartLine
              isResolved
              isCollapsed
              isOutdated
              comments(first:100) {
                nodes {
                  id
                  body
                  diffHunk
                  createdAt
                  lastEditedAt
                  commit { abbreviatedOid }
                  author {login}
                  authorAssociation
                  viewerDidAuthor
                  viewerCanUpdate
                  viewerCanDelete
                  state
                  replyTo { id }
                  pullRequestReview {
                    id
                    state
                  }
                  path
                  reactionGroups {
                    content
                    viewerHasReacted
                    users {
                      totalCount
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
]]

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
M.delete_issue_comment_mutation = [[
  mutation {
    deleteIssueComment(input: {id: "%s"}) {
      clientMutationId
    }
  }
]]

-- https://docs.github.com/en/graphql/reference/mutations#deletepullrequestreviewcomment
M.delete_pull_request_review_comment_mutation = [[
  mutation {
    deletePullRequestReviewComment(input: {id: "%s"}) {
      pullRequestReview {
        id
        pullRequest {
          id
          reviewThreads(last:100) {
            nodes {	
              id
              path
              diffSide
              startDiffSide
              line
              originalLine
              startLine
              originalStartLine
              isResolved
              isCollapsed
              isOutdated
              comments(first:100) {
                nodes {
                  id
                  body
                  diffHunk
                  createdAt
                  lastEditedAt
                  commit { abbreviatedOid }
                  author {login}
                  authorAssociation
                  viewerDidAuthor
                  viewerCanUpdate
                  viewerCanDelete
                  state
                  replyTo { id }
                  pullRequestReview {
                    id
                    state
                  }
                  path
                  reactionGroups {
                    content
                    viewerHasReacted
                    users {
                      totalCount
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
]]

-- https://docs.github.com/en/free-pro-team@latest/graphql/reference/mutations#updateissue
M.update_issue_mutation = [[
  mutation {
    updateIssue(input: {id: "%s", title: "%s", body: "%s"}) {
      issue {
        id
        number
        state
        title
        body
        repository { nameWithOwner }
      }
    }
  }
]]
-- https://docs.github.com/en/free-pro-team@latest/graphql/reference/mutations#createissue
M.create_issue_mutation = [[
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
        viewerDidAuthor
        viewerCanUpdate
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
        repository {
          nameWithOwner
        }
        timelineItems(first: 100) {
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

-- https://docs.github.com/en/free-pro-team@latest/graphql/reference/mutations#updateissue
M.update_issue_mutation = [[
  mutation {
    updateIssue(input: {id: "%s", title: "%s", body: "%s"}) {
      issue {
        id
        number
        state
        title
        body
        repository {
          nameWithOwner
        }
      }
    }
  }
]]

-- https://docs.github.com/en/free-pro-team@latest/graphql/reference/mutations#updateissue
M.update_issue_state_mutation = [[
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
        comments(first: 100) {
          nodes {
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
        timelineItems(last: 100) {
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
      }
    }
  }
]]

-- https://docs.github.com/en/free-pro-team@latest/graphql/reference/mutations#updatepullrequest
M.update_pull_request_mutation = [[
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
M.update_pull_request_state_mutation = [[
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
        files(first:100) {
          nodes {
            path
            viewerViewedState 
          } 
        }
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
          name
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
          viewerHasReacted
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
              viewerHasReacted
              users {
                totalCount
              }
            }
            author {
              login
            }
            viewerDidAuthor
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
        timelineItems(last: 100) {
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
            ... on PullRequestCommit {
              commit {
                messageHeadline
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
            ... on ReopenedEvent {
              createdAt
              actor {
                login
              }
            }
            ... on ReviewRequestedEvent {
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
            ... on ReviewRequestRemovedEvent {
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
            ... on ReviewDismissedEvent {
              createdAt
              actor {
                login
              }
              dismissalMessage
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
            ... on PullRequestReview {
              id
              body
              createdAt
              viewerCanUpdate
              viewerCanDelete
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
              state
              comments(last:100) {
                totalCount
                nodes{
                  id
                  replyTo { id }
                  body
                  commit {
                    oid
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
                  reactionGroups {
                    content
                    viewerHasReacted
                    users {
                      totalCount
                    }
                  }
                }
              }
            }
          }
        }
        reviewRequests(first: 20) {
          totalCount
          nodes {
            requestedReviewer {
              ... on User {
                login
                isViewer
              }
              ... on Mannequin { login }
              ... on Team { name }
            }
          }
        }
      }
    }
  }
]]

-- https://docs.github.com/en/graphql/reference/objects#pullrequestreviewthread
M.pending_review_threads_query = [[
query { 
  repository(owner:"%s", name:"%s") {
    pullRequest (number: %d){
      reviews(first:100, states:PENDING) {
        nodes {
          id
          viewerDidAuthor
        }
      }
      reviewThreads(last:100) {
        nodes {	
          id
          path
          diffSide
          startDiffSide
          line
          originalLine
          startLine
          originalStartLine
          isResolved
          isCollapsed
          isOutdated
          comments(first:100) {
            nodes {
              id
              body
              diffHunk
              createdAt
              lastEditedAt
              commit { abbreviatedOid }
              author {login}
              authorAssociation
              viewerDidAuthor
              viewerCanUpdate
              viewerCanDelete
              state
              replyTo { id }
              pullRequestReview {
                id
                state
              }
              path
              reactionGroups {
                content
                viewerHasReacted
                users {
                  totalCount
                }
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
M.review_threads_query = [[
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
              lastEditedAt
              state
              commit {
                oid
              }
              pullRequestReview {
                id
                state
              }
              path
              replyTo { id }
              author { login }
              authorAssociation
              viewerDidAuthor
              viewerCanUpdate
              viewerCanDelete
              outdated
              diffHunk
              reactionGroups {
                content
                viewerHasReacted
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
M.pull_request_query = [[
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
      repository { nameWithOwner }
      files(first:100) {
        nodes {
          path
          viewerViewedState 
        } 
      }
      merged
      mergedBy {
        ... on Organization { name }
        ... on Bot { login }
        ... on User {
          login
          isViewer
        }
        ... on Mannequin { login }
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
        name
        nameWithOwner
      }
      milestone {
        title
        state
      }
      author {
        login
      }
      viewerDidAuthor
      viewerCanUpdate
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
          ... on PullRequestCommit {
            commit {
              messageHeadline
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
          ... on ReopenedEvent {
            createdAt
            actor {
              login
            }
          }
          ... on ReviewRequestedEvent {
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
          ... on ReviewRequestRemovedEvent {
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
          ... on ReviewDismissedEvent {
            createdAt
            actor {
              login
            }
            dismissalMessage
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
          ... on PullRequestReview {
            id
            body
            createdAt
            viewerCanUpdate
            viewerCanDelete
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
            state
            comments(last:100) {
              totalCount
              nodes{
                id
                replyTo { id }
                body
                commit {
                  oid
                }
                author { login }
                createdAt
                lastEditedAt
                authorAssociation
                viewerDidAuthor
                viewerCanUpdate
                viewerCanDelete
                originalPosition
                position
                state
                outdated
                diffHunk
                reactionGroups {
                  content
                  viewerHasReacted
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
              lastEditedAt
              replyTo { id }
              state
              commit {
                oid
              }
              pullRequestReview {
                id
                state
              }
              path
              author { login }
              authorAssociation
              viewerDidAuthor
              viewerCanUpdate
              viewerCanDelete
              outdated
              diffHunk
              reactionGroups {
                content
                viewerHasReacted
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
          isViewer
        }
      }
      reviewRequests(first: 20) {
        totalCount
        nodes {
          requestedReviewer {
            ... on User {
              login
              isViewer
            }
            ... on Mannequin { login }
            ... on Team { name }
          }
        }
      }
    }
  }
}
]]

-- https://docs.github.com/en/graphql/reference/unions#issueorpullrequest
M.issue_kind_query = [[
query { 
  repository(owner: "%s", name: "%s") {
    issueOrPullRequest(number: %d) {
      __typename
    }
  }
}
]]

-- https://docs.github.com/en/graphql/reference/unions#issueorpullrequest
M.issue_summary_query = [[
query { 
  repository(owner: "%s", name: "%s") {
    issueOrPullRequest(number: %d) {
      ... on PullRequest {
        __typename
        headRefName
        baseRefName
        createdAt
        state
        number
        title
        body
        repository { nameWithOwner }
        author { login }
        authorAssociation
        labels(first: 20) {
          nodes {
            color
            name
          }
        }
      }
      ... on Issue {
        __typename
        createdAt
        state
        number
        title
        body
        repository { nameWithOwner }
        author { login }
        authorAssociation
        labels(first: 20) {
          nodes {
            color
            name
          }
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


M.pull_requests_query = [[
query($endCursor: String) {
  repository(owner: "%s", name: "%s") {
    pullRequests(first: 100, after: $endCursor, %s) {
      nodes {
        __typename
        number
        title
        url
        repository { nameWithOwner }
        headRefName
      }
      pageInfo {
        hasNextPage
        endCursor
      }
    }
  }
}
]]

M.search_query = [[
query {
  search(query: "%s", type: ISSUE, last: 100) {
    nodes {
      ... on Issue{
        __typename
        number
        url
        title
        repository { nameWithOwner }
      }
      ... on PullRequest {
        __typename
        number
        title
        url
        repository { nameWithOwner }
      }
    }
  }
}
]]

-- https://docs.github.com/en/graphql/reference/objects#project
M.projects_query = [[
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
M.add_project_card_mutation = [[
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
M.move_project_card_mutation = [[
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
M.delete_project_card_mutation = [[
  mutation {
    deleteProjectCard(input: {cardId: "%s"}) {
      deletedCardId
    }
  }
]]

-- https://docs.github.com/en/graphql/reference/mutations#createlabel
-- requires application/vnd.github.bane-preview+json
M.create_label_mutation = [[
  mutation {
    createLabel(input: {repositoryId: "%s", name: "%s", description: "%s", color: "%s"}) {
      label {
        id
        name
      }
    }
  }
]]

-- https://docs.github.com/en/graphql/reference/mutations#removelabelsfromlabelable
M.add_labels_mutation = [[
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
M.remove_labels_mutation = [[
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
M.labels_query = [[
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

M.issue_labels_query = [[
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

M.pull_request_labels_query = [[
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

M.issue_assignees_query = [[
  query {
    repository(owner: "%s", name: "%s") {
      issue(number: %d) {
        assignees(first: 100) {
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

M.pull_request_assignees_query = [[
  query {
    repository(owner: "%s", name: "%s") {
      pullRequest(number: %d) {
        assignees(first: 100) {
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

-- https://docs.github.com/en/graphql/reference/mutations#addassigneestoassignable
M.add_assignees_mutation = [[
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
M.remove_assignees_mutation = [[
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
M.request_reviews_mutation = [[
  mutation {
    requestReviews(input: {pullRequestId: "%s", userIds: ["%s"]}) {
      pullRequest {
        id
      }
    }
  }
]]

M.user_profile_query = [[
query {
  user(login: "%s") {
    login
    bio
    company
    followers(first: 1) {
      totalCount
    }
    following(first: 1) {
      totalCount
    }
    hovercard {
      contexts {
        message
      }
    }
    hasSponsorsListing
    isEmployee
    isViewer
    location
    organizations(last: 5) {
      nodes {
        name
      }
    }
    name
    status {
      emoji
      message
    }
    twitterUsername
    websiteUrl
  }
}
]]

M.changed_files_query = [[
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

M.file_content_query = [[
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

M.reactions_for_object_query = [[
query {
  node(id: "%s") {
    ... on Issue {
      reactionGroups {
        content
        users(last: 100) {
          nodes {
            login
          }
        }
      }
    }
    ... on PullRequest {
      reactionGroups {
        content
        users(last: 100) {
          nodes {
            login
          }
        }
      }
    }
    ... on PullRequestReviewComment {
      reactionGroups {
        content
        users(last: 100) {
          nodes {
            login
          }
        }
      }
    }
    ... on PullRequestReview {
      reactionGroups {
        content
        users(last: 100) {
          nodes {
            login
          }
        }
      }
    }
    ... on IssueComment {
      reactionGroups {
        content
        users(last: 100) {
          nodes {
            login
          }
        }
      }
    }
  }
}
]]

M.users_query = [[
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

M.repos_query = [[
query($endCursor: String) {
  repositoryOwner(login: "%s") {
    repositories(first: 100, after: $endCursor, ownerAffiliations: [COLLABORATOR, ORGANIZATION_MEMBER, OWNER]) {
      nodes {
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
      pageInfo {
        hasNextPage
        endCursor
      }
    }
  }
}
]]

M.repository_query = [[
query {
  repository(owner: "%s", name: "%s") {
    id
    nameWithOwner
    description
    forkCount
    stargazerCount
    diskUsage
    createdAt
    updatedAt
    pushedAt
    isFork
    defaultBranchRef {
      name
    }
    parent {
      nameWithOwner
    }
    isArchived
    isDisabled
    isPrivate
    isEmpty
    isInOrganization
    isSecurityPolicyEnabled
    securityPolicyUrl
    defaultBranchRef {
      name
    }
    url
    isLocked
    lockReason
    isMirror
    mirrorUrl
    hasProjectsEnabled
    projectsUrl
    homepageUrl
    primaryLanguage {
      name
      color
    }
    refs(last:100, refPrefix: "refs/heads/") {
      nodes {
        name
      }
    }
    languages(first:100) {
      nodes {
        name
        color
      }
    }
  }
}
]]

M.gists_query = [[
query($endCursor: String) {
  viewer {
    gists(first: 100, privacy: %s, after: $endCursor) {
      nodes {
        name
        isPublic
        isFork
        description
        createdAt
        files {
          encodedName
          encoding
          extension
          name
          size
          text
        }
      }
      pageInfo {
        hasNextPage
        endCursor
      }
    }
  }
}
]]

-- https://docs.github.com/en/graphql/reference/mutations#createpullrequest
M.create_pr_mutation = [[
	mutation {
		createPullRequest(input: {baseRefName: "%s", headRefName: "%s", repositoryId: "%s", title: "%s", body: "%s", draft: %s}) {
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
        files(first:100) {
          nodes {
            path
            viewerViewedState 
          } 
        }
        merged
        mergedBy {
          ... on Organization { name }
          ... on Bot { login }
          ... on User {
            login
            isViewer
          }
          ... on Mannequin { login }
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
          name
          nameWithOwner
        }
        milestone {
          title
          state
        }
        author {
          login
        }
        viewerDidAuthor
        viewerCanUpdate
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
        timelineItems(first: 100) {
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
            ... on PullRequestCommit {
              commit {
                messageHeadline
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
            ... on ReopenedEvent {
              createdAt
              actor {
                login
              }
            }
            ... on ReviewRequestedEvent {
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
            ... on ReviewRequestRemovedEvent {
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
            ... on ReviewDismissedEvent {
              createdAt
              actor {
                login
              }
              dismissalMessage
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
            ... on PullRequestReview {
              id
              body
              createdAt
              viewerCanUpdate
              viewerCanDelete
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
              state
              comments(last:100) {
                totalCount
                nodes{
                  id
                  replyTo { id }
                  body
                  commit {
                    oid
                  }
                  author { login }
                  createdAt
                  lastEditedAt
                  authorAssociation
                  viewerDidAuthor
                  viewerCanUpdate
                  viewerCanDelete
                  originalPosition
                  position
                  state
                  outdated
                  diffHunk
                  reactionGroups {
                    content
                    viewerHasReacted
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
                lastEditedAt
                replyTo { id }
                state
                commit {
                  oid
                }
                pullRequestReview {
                  id
                  state
                }
                path
                author { login }
                authorAssociation
                viewerDidAuthor
                viewerCanUpdate
                viewerCanDelete
                outdated
                diffHunk
                reactionGroups {
                  content
                  viewerHasReacted
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
            isViewer
          }
        }
        reviewRequests(first: 20) {
          totalCount
          nodes {
            requestedReviewer {
              ... on User {
                login
                isViewer
              }
              ... on Mannequin { login }
              ... on Team { name }
            }
          }
        }
      }
    }
	}
]]

-- https://docs.github.com/en/graphql/reference/queries#user
M.user_query = [[
query { 
  user(login:"%s") {
    id
  }
}
]]

-- https://docs.github.com/en/graphql/reference/objects#pullrequestreviewthread
M.repo_labels_query = [[
query { 
  repository(owner:"%s", name:"%s") {
    labels(first: 100) {
      nodes {
        id
        name
      }
    }
  }
}
]]

local function escape_chars(string)
  local escaped, _ = string.gsub(string, '["\\]', {
    ['"'] = '\\"',
    ["\\"] = "\\\\",
  })
  return escaped
end

return function(query, ...)
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
