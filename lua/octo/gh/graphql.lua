local fragments = require "octo.gh.fragments"

local M = {}

-- https://docs.github.com/en/graphql/reference/mutations#addreaction
M.add_reaction_mutation = [[
  mutation {
    addReaction(input: {subjectId: "%s", content: %s}) {
      subject {
        ...ReactionGroupsFragment
      }
    }
  }
]] .. fragments.reaction_groups

-- https://docs.github.com/en/graphql/reference/mutations#removereaction
M.remove_reaction_mutation = [[
  mutation {
    removeReaction(input: {subjectId: "%s", content: %s}) {
      subject {
        ...ReactionGroupsFragment
      }
    }
  }
]] .. fragments.reaction_groups

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
              ...ReviewThreadInformationFragment
              comments(first:100) {
                nodes {
                  ...ReviewThreadCommentFragment
                }
              }
            }
          }
        }
      }
    }
  }
]] .. fragments.reaction_groups .. fragments.review_thread_information .. fragments.review_thread_comment

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
              ...ReviewThreadInformationFragment
              comments(first:100) {
                nodes {
                  ...ReviewThreadCommentFragment
                }
              }
            }
          }
        }
      }
    }
  }
]] .. fragments.reaction_groups .. fragments.review_thread_information .. fragments.review_thread_comment

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
              ...ReviewThreadInformationFragment
              comments(first:100) {
                nodes {
                  ...ReviewThreadCommentFragment
                }
              }
            }
          }
        }
      }
    }
  }
]] .. fragments.reaction_groups .. fragments.review_thread_information .. fragments.review_thread_comment

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
    submitPullRequestReview(input: {pullRequestReviewId: "%s", event: %s, body: """%s"""}) {
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
  addPullRequestReviewThread(input: { pullRequestReviewId: "%s", body: """%s""", path: "%s", side: %s, line:%d}) {
    thread {
      id
      comments(last:100) {
        nodes {
          id
          body
          diffHunk
          createdAt
          lastEditedAt
          commit {
            oid
            abbreviatedOid
          }
          author {login}
          authorAssociation
          viewerDidAuthor
          viewerCanUpdate
          viewerCanDelete
          state
          url
          replyTo { id url }
          pullRequestReview {
            id
            state
          }
          path
          ...ReactionGroupsFragment
        }
      }
      pullRequest {
        reviewThreads(last:100) {
          nodes {
            ...ReviewThreadInformationFragment
            comments(first:100) {
              nodes {
                ...ReviewThreadCommentFragment
              }
            }
          }
        }
      }
    }
  }
}
]] .. fragments.reaction_groups .. fragments.review_thread_information .. fragments.review_thread_comment

-- https://docs.github.com/en/graphql/reference/mutations#addpullrequestreviewthread
M.add_pull_request_review_multiline_thread_mutation = [[
mutation {
  addPullRequestReviewThread(input: { pullRequestReviewId: "%s", body: """%s""", path: "%s", startSide: %s, side: %s, startLine: %d, line:%d}) {
    thread {
      id
      comments(last:100) {
        nodes {
          id
          body
          diffHunk
          createdAt
          lastEditedAt
          commit {
            oid
            abbreviatedOid
          }
          author {login}
          authorAssociation
          viewerDidAuthor
          viewerCanUpdate
          viewerCanDelete
          state
          url
          replyTo { id url }
          pullRequestReview {
            id
            state
          }
          path
          ...ReactionGroupsFragment
        }
      }
      pullRequest {
        reviewThreads(last:100) {
          nodes {
            ...ReviewThreadInformationFragment
            comments(first:100) {
              nodes {
                ...ReviewThreadCommentFragment
              }
            }
          }
        }
      }
    }
  }
}
]] .. fragments.reaction_groups .. fragments.review_thread_information .. fragments.review_thread_comment

-- https://docs.github.com/en/graphql/reference/mutations#addcomment
M.add_issue_comment_mutation = [[
  mutation {
    addComment(input: {subjectId: "%s", body: """%s"""}) {
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
    updateIssueComment(input: {id: "%s", body: """%s"""}) {
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
    updatePullRequestReviewComment(input: {pullRequestReviewCommentId: "%s", body: """%s"""}) {
      pullRequestReviewComment {
        id
        body
        pullRequest {
          reviewThreads(last:100) {
            nodes {
              ...ReviewThreadInformationFragment
              comments(first:100) {
                nodes {
                  ...ReviewThreadCommentFragment
                }
              }
            }
          }
        }
      }
    }
  }
]] .. fragments.reaction_groups .. fragments.review_thread_information .. fragments.review_thread_comment

-- https://docs.github.com/en/graphql/reference/mutations#updatepullrequestreview
M.update_pull_request_review_mutation = [[
  mutation {
    updatePullRequestReview(input: {pullRequestReviewId: "%s", body: """%s"""}) {
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
    addPullRequestReviewComment(input: {inReplyTo: "%s", body: """%s""", pullRequestReviewId: "%s"}) {
      comment {
        id
        body
        pullRequest {
          reviewThreads(last:100) {
            nodes {
              ...ReviewThreadInformationFragment
              comments(first:100) {
                nodes {
                  ...ReviewThreadCommentFragment
                }
              }
            }
          }
        }
      }
    }
  }
]] .. fragments.reaction_groups .. fragments.review_thread_information .. fragments.review_thread_comment

-- https://docs.github.com/en/graphql/reference/mutations#addpullrequestreviewcomment
M.add_pull_request_review_commit_thread_mutation = [[
  mutation {
    addPullRequestReviewComment(input: {commitOID: "%s", body: """%s""", pullRequestReviewId: "%s", path: "%s", position: %d }) {
      comment {
        id
        body
        pullRequest {
          reviewThreads(last:100) {
            nodes {
              ...ReviewThreadInformationFragment
              comments(first:100) {
                nodes {
                  ...ReviewThreadCommentFragment
                }
              }
            }
          }
        }
      }
    }
  }
]] .. fragments.reaction_groups .. fragments.review_thread_information .. fragments.review_thread_comment

-- M.add_pull_request_review_comment_mutation =
-- [[
--   mutation {
--     addPullRequestReviewThreadReply(input: { pullRequestReviewThreadId: "%s", body: """%s"""}) {
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
              ...ReviewThreadInformationFragment
              comments(first:100) {
                nodes {
                  ...ReviewThreadCommentFragment
                }
              }
            }
          }
        }
      }
    }
  }
]] .. fragments.reaction_groups .. fragments.review_thread_information .. fragments.review_thread_comment

-- https://docs.github.com/en/free-pro-team@latest/graphql/reference/mutations#updateissue
M.update_issue_mutation = [[
mutation {
  updateIssue(input: {id: "%s", title: """%s""", body: """%s"""}) {
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
-- https://docs.github.com/en/free-pro-team@latest/graphql/reference/mutations#createissue
M.create_issue_mutation = [[
  mutation {
    createIssue(input: {repositoryId: "%s", title: """%s""", body: """%s"""}) {
      issue {
        ...IssueInformationFragment
        participants(first:10) {
          nodes {
            login
          }
        }
        ...ReactionGroupsFragment
        projectCards(last: 20) {
          nodes {
            ...ProjectCardFragment
          }
        }
        repository {
          nameWithOwner
        }
        timelineItems(first: 100) {
          ...IssueTimelineItemsConnectionFragment
        }
        labels(first: 20) {
          ...LabelConnectionFragment
        }
        assignees(first: 20) {
          ...AssigneeConnectionFragment
        }
      }
    }
  }
]] .. fragments.cross_referenced_event .. fragments.issue .. fragments.pull_request .. fragments.connected_event .. fragments.milestoned_event .. fragments.demilestoned_event .. fragments.reaction_groups .. fragments.label_connection .. fragments.label .. fragments.assignee_connection .. fragments.issue_comment .. fragments.assigned_event .. fragments.labeled_event .. fragments.unlabeled_event .. fragments.closed_event .. fragments.reopened_event .. fragments.project_cards .. fragments.issue_timeline_items_connection .. fragments.renamed_title_event .. fragments.issue_information .. fragments.referenced_event

M.close_issue_mutation = [[
mutation {
  closeIssue(input: {issueId: "%s", stateReason: %s}) {
    issue {
      ...IssueInformationFragment
      participants(first:10) {
        nodes {
          login
        }
      }
      ...ReactionGroupsFragment
      comments(first: 100) {
        nodes {
          id
          body
          createdAt
          ...ReactionGroupsFragment
          author {
            login
          }
          viewerDidAuthor
        }
      }
      labels(first: 20) {
        ...LabelConnectionFragment
      }
      assignees(first: 20) {
        ...AssigneeConnectionFragment
      }
      timelineItems(last: 100) {
        ...IssueTimelineItemsConnectionFragment
      }
    }
  }
}
]] .. fragments.cross_referenced_event .. fragments.issue .. fragments.pull_request .. fragments.connected_event .. fragments.milestoned_event .. fragments.demilestoned_event .. fragments.label_connection .. fragments.label .. fragments.reaction_groups .. fragments.assignee_connection .. fragments.issue_comment .. fragments.assigned_event .. fragments.labeled_event .. fragments.unlabeled_event .. fragments.closed_event .. fragments.reopened_event .. fragments.issue_timeline_items_connection .. fragments.issue_information .. fragments.renamed_title_event .. fragments.referenced_event

-- https://docs.github.com/en/free-pro-team@latest/graphql/reference/mutations#updateissue
M.update_issue_state_mutation = [[
  mutation {
    updateIssue(input: {id: "%s", state: %s}) {
      issue {
        ...IssueInformationFragment
        participants(first:10) {
          nodes {
            login
          }
        }
        ...ReactionGroupsFragment
        comments(first: 100) {
          nodes {
            id
            body
            createdAt
            ...ReactionGroupsFragment
            author {
              login
            }
            viewerDidAuthor
          }
        }
        labels(first: 20) {
          ...LabelConnectionFragment
        }
        assignees(first: 20) {
          ...AssigneeConnectionFragment
        }
        timelineItems(last: 100) {
          ...IssueTimelineItemsConnectionFragment
        }
      }
    }
  }
]] .. fragments.cross_referenced_event .. fragments.issue .. fragments.pull_request .. fragments.connected_event .. fragments.milestoned_event .. fragments.demilestoned_event .. fragments.reaction_groups .. fragments.label_connection .. fragments.label .. fragments.assignee_connection .. fragments.issue_comment .. fragments.assigned_event .. fragments.labeled_event .. fragments.unlabeled_event .. fragments.closed_event .. fragments.reopened_event .. fragments.issue_timeline_items_connection .. fragments.issue_information .. fragments.renamed_title_event .. fragments.referenced_event

-- https://docs.github.com/en/graphql/reference/mutations#reopenissue
M.reopen_issue_mutation = [[
mutation($issueId: ID!) {
  reopenIssue(input: {
    issueId: $issueId
  }) {
    issue {
      ...IssueInformationFragment
      participants(first:10) {
        nodes {
          login
        }
      }
      ...ReactionGroupsFragment
      comments(first: 100) {
        nodes {
          id
          body
          createdAt
          ...ReactionGroupsFragment
          author {
            login
          }
          viewerDidAuthor
        }
      }
      labels(first: 20) {
        ...LabelConnectionFragment
      }
      assignees(first: 20) {
        ...AssigneeConnectionFragment
      }
      timelineItems(last: 100) {
        ...IssueTimelineItemsConnectionFragment
      }
    }
  }
}
]] .. fragments.cross_referenced_event .. fragments.issue .. fragments.pull_request .. fragments.connected_event .. fragments.milestoned_event .. fragments.demilestoned_event .. fragments.reaction_groups .. fragments.label_connection .. fragments.label .. fragments.assignee_connection .. fragments.issue_comment .. fragments.assigned_event .. fragments.labeled_event .. fragments.unlabeled_event .. fragments.closed_event .. fragments.reopened_event .. fragments.issue_timeline_items_connection .. fragments.issue_information .. fragments.renamed_title_event .. fragments.referenced_event

-- https://docs.github.com/en/free-pro-team@latest/graphql/reference/mutations#updatepullrequest
M.update_pull_request_mutation = [[
  mutation {
    updatePullRequest(input: {pullRequestId: "%s", title: """%s""", body: """%s"""}) {
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
        isDraft
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
        ...ReactionGroupsFragment
        comments(first: 100) {
          nodes {
            id
            body
            createdAt
            ...ReactionGroupsFragment
            author {
              login
            }
            viewerDidAuthor
          }
        }
        labels(first: 20) {
          ...LabelConnectionFragment
        }
        assignees(first: 20) {
          ...AssigneeConnectionFragment
        }
        timelineItems(last: 100) {
          ...PullRequestTimelineItemsConnectionFragment
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
]] .. fragments.cross_referenced_event .. fragments.issue .. fragments.pull_request .. fragments.connected_event .. fragments.milestoned_event .. fragments.demilestoned_event .. fragments.reaction_groups .. fragments.label_connection .. fragments.label .. fragments.assignee_connection .. fragments.issue_comment .. fragments.assigned_event .. fragments.labeled_event .. fragments.unlabeled_event .. fragments.closed_event .. fragments.reopened_event .. fragments.pull_request_review .. fragments.pull_request_commit .. fragments.review_request_removed_event .. fragments.merged_event .. fragments.review_requested_event .. fragments.renamed_title_event .. fragments.review_dismissed_event .. fragments.pull_request_timeline_items_connection

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
          ...ReviewThreadInformationFragment
          comments(first:100) {
            nodes {
              ...ReviewThreadCommentFragment
            }
          }
        }
      }
    }
  }
}
]] .. fragments.reaction_groups .. fragments.review_thread_information .. fragments.review_thread_comment

-- https://docs.github.com/en/free-pro-team@latest/graphql/reference/objects#pullrequestreviewthread
M.review_threads_query = [[
query($endCursor: String) {
  repository(owner:"%s", name:"%s") {
    pullRequest(number:%d) {
      reviewThreads(last:80) {
        nodes {
          ...ReviewThreadInformationFragment
          comments(first: 100, after: $endCursor) {
            nodes {
              ...ReviewThreadCommentFragment
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
]] .. fragments.reaction_groups .. fragments.review_thread_information .. fragments.review_thread_comment

-- https://docs.github.com/en/free-pro-team@latest/graphql/reference/objects#pullrequest
M.pull_request_query = [[
query($endCursor: String) {
  repository(owner: "%s", name: "%s") {
    pullRequest(number: %d) {
      id
      isDraft
      number
      state
      title
      body
      createdAt
      closedAt
      updatedAt
      url
      headRepository { nameWithOwner }
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
      ...ReactionGroupsFragment
      projectCards(last: 20) {
        nodes {
          ...ProjectCardFragment
        }
      }
      %s
      timelineItems(first: 100, after: $endCursor) {
        pageInfo {
          hasNextPage
          endCursor
        }
        ...PullRequestTimelineItemsConnectionFragment
      }
      reviewDecision
      reviewThreads(last:100) {
        nodes {
          ...ReviewThreadInformationFragment
          comments(first: 100) {
            nodes {
              ...ReviewThreadCommentFragment
            }
          }
        }
      }
      labels(first: 20) {
        ...LabelConnectionFragment
      }
      assignees(first: 20) {
        ...AssigneeConnectionFragment
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
      statusCheckRollup {
        state
      }
      mergeStateStatus
      mergeable
      autoMergeRequest {
        enabledBy { login }
        mergeMethod
      }
    }
  }
}
]] .. fragments.cross_referenced_event .. fragments.issue .. fragments.pull_request .. fragments.connected_event .. fragments.milestoned_event .. fragments.demilestoned_event .. fragments.reaction_groups .. fragments.label_connection .. fragments.label .. fragments.assignee_connection .. fragments.issue_comment .. fragments.assigned_event .. fragments.labeled_event .. fragments.unlabeled_event .. fragments.closed_event .. fragments.reopened_event .. fragments.pull_request_review .. fragments.project_cards .. fragments.pull_request_commit .. fragments.review_request_removed_event .. fragments.review_requested_event .. fragments.merged_event .. fragments.renamed_title_event .. fragments.review_dismissed_event .. fragments.pull_request_timeline_items_connection .. fragments.review_thread_information .. fragments.review_thread_comment

-- https://docs.github.com/en/free-pro-team@latest/graphql/reference/objects#issue
M.issue_query = [[
query($endCursor: String) {
  repository(owner: "%s", name: "%s") {
    issue(number: %d) {
      ...IssueInformationFragment
      participants(first:10) {
        nodes {
          login
        }
      }
      ...ReactionGroupsFragment
      projectCards(last: 20) {
        nodes {
          ...ProjectCardFragment
        }
      }
      %s
      timelineItems(first: 100, after: $endCursor) {
        pageInfo {
          hasNextPage
          endCursor
        }
        ...IssueTimelineItemsConnectionFragment
      }
      labels(first: 20) {
        ...LabelConnectionFragment
      }
      assignees(first: 20) {
        ...AssigneeConnectionFragment
      }
    }
  }
}
]] .. fragments.cross_referenced_event .. fragments.issue .. fragments.pull_request .. fragments.connected_event .. fragments.milestoned_event .. fragments.demilestoned_event .. fragments.reaction_groups .. fragments.label .. fragments.label_connection .. fragments.assignee_connection .. fragments.issue_comment .. fragments.assigned_event .. fragments.labeled_event .. fragments.unlabeled_event .. fragments.closed_event .. fragments.reopened_event .. fragments.project_cards .. fragments.renamed_title_event .. fragments.issue_timeline_items_connection .. fragments.issue_information .. fragments.referenced_event

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
          ...LabelConnectionFragment
        }
      }
      ... on Issue {
        __typename
        createdAt
        state
        stateReason
        number
        title
        body
        repository { nameWithOwner }
        author { login }
        authorAssociation
        labels(first: 20) {
          ...LabelConnectionFragment
        }
      }
    }
  }
}
]] .. fragments.label_connection .. fragments.label

-- https://docs.github.com/en/free-pro-team@latest/graphql/reference/objects#repository
M.repository_id_query = [[
query {
  repository(owner: "%s", name: "%s") {
    id
  }
}
]]

-- https://docs.github.com/en/free-pro-team@latest/graphql/reference/objects#repository
-- https://docs.github.com/en/graphql/reference/objects#issuetemplate
-- https://docs.github.com/en/graphql/reference/objects#pullrequesttemplate
M.repository_templates_query = [[
query {
  repository(owner: "%s", name: "%s") {
    issueTemplates { body about name title  }
    pullRequestTemplates { body filename }
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
    issues(first: 100, after: $endCursor, filterBy: {%s}, orderBy: {field: %s, direction: %s}) {
      nodes {
        __typename
        number
        title
        url
        repository { nameWithOwner }
        state
        stateReason
      }
      pageInfo {
        hasNextPage
        endCursor
      }
    }
  }
}
]]
M.pull_requests_query = [[
query($endCursor: String) {
  repository(owner: "%s", name: "%s") {
    pullRequests(first: 100, after: $endCursor, %s, orderBy: {field: %s, direction: %s}) {
      nodes {
        __typename
        number
        title
        url
        repository { nameWithOwner }
        headRefName
        isDraft
        state
      }
      pageInfo {
        hasNextPage
        endCursor
      }
    }
  }
}
]]

M.search_count_query = [[
query {
  search(query: """%s""", type: ISSUE, last: 100) {
    issueCount
  }
}
]]

M.search_query = [[
query {
  search(query: """%s""", type: ISSUE, last: 100) {
    nodes {
      ... on Issue{
        __typename
        number
        url
        title
        state
        repository { nameWithOwner }
        stateReason
      }
      ... on PullRequest {
        __typename
        number
        title
        url
        state
        isDraft
        repository { nameWithOwner }
      }
    }
  }
}
]]

M.discussions_query = [[
query(
  $owner: String!,
  $name: String!,
  $states: [DiscussionState!],
  $orderBy: DiscussionOrderField!,
  $direction: OrderDirection!,
  $endCursor: String
) {
  repository(owner: $owner, name: $name) {
    discussions(first: 100, after: $endCursor, states: $states, orderBy: {field: $orderBy, direction: $direction}) {
      nodes {
        __typename
        ...DiscussionInfoFragment
        answer {
          author {
            login
          }
          body
        }
      }
      pageInfo {
        hasNextPage
        endCursor
      }
    }
  }
}
]] .. fragments.discussion_info

M.discussion_query = [[
query($endCursor: String) {
  repository(owner: "%s", name: "%s") {
    discussion(number: %d) {
      ...DiscussionDetailsFragment
      labels(first: 20) {
        ...LabelConnectionFragment
      }
      comments(first: 100, after: $endCursor) {
        totalCount
        nodes {
          ...DiscussionCommentFragment
          replies(first: 10) {
            totalCount
            nodes {
              body
              author {
                login
              }
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
]] .. fragments.reaction_groups .. fragments.label_connection .. fragments.label .. fragments.discussion_info .. fragments.discussion_details .. fragments.discussion_comment

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

-- https://docs.github.com/en/graphql/reference/objects#projectv2
M.projects_query_v2 = [[
query {
  repository(owner: "%s", name: "%s") {
    projects: projectsV2(first: 100) {
      nodes {
        id
        title
        url
        closed
        number
        owner {
          ... on User {
            login
          }
          ... on Organization {
            login
          }
        }
        columns: field(name: "Status") {
          ... on ProjectV2SingleSelectField {
            id
            options {
              id
              name
            }
          }
        }
      }
    }
  }
  user(login: "%s") {
    projects: projectsV2(first: 100) {
      nodes {
        id
        title
        url
        closed
        number
        owner {
          ... on User {
            login
          }
          ... on Organization {
            login
          }
        }
        columns: field(name: "Status") {
          ... on ProjectV2SingleSelectField {
            id
            options {
              id
              name
            }
          }
        }
      }
    }
  }
  organization(login: "%s") {
    projects: projectsV2(first: 100) {
      nodes {
        id
        title
        url
        closed
        number
        owner {
          ... on User {
            login
          }
          ... on Organization {
            login
          }
        }
        columns: field(name: "Status") {
          ... on ProjectV2SingleSelectField {
            id
            options {
              id
              name
            }
          }
        }
      }
    }
  }
}
]]

-- https://docs.github.com/en/graphql/reference/mutations#addprojectv2itembyid
M.add_project_v2_item_mutation = [[
  mutation {
    addProjectV2ItemById(input: {contentId: "%s", projectId: "%s"}) {
      item {
        id
      }
    }
  }
]]

-- https://docs.github.com/en/graphql/reference/mutations#updateprojectv2itemfieldvalue
M.update_project_v2_item_mutation = [[
  mutation {
    updateProjectV2ItemFieldValue(
      input: {
        projectId: "%s",
        itemId: "%s",
        fieldId: "%s",
        value: { singleSelectOptionId: "%s" }
      }
    ) {
      projectV2Item {
        id
      }
    }
  }
]]

-- https://docs.github.com/en/graphql/reference/mutations#deleteprojectv2item
M.delete_project_v2_item_mutation = [[
  mutation {
    deleteProjectV2Item(input: {projectId: "%s", itemId: "%s"}) {
      deletedItemId
    }
  }
]]

-- https://docs.github.com/en/graphql/reference/mutations#createlabel
-- requires application/vnd.github.bane-preview+json
M.create_label_mutation = [[
  mutation {
    createLabel(input: {repositoryId: "%s", name: "%s", description: """%s""", color: "%s"}) {
      label {
        ...LabelFragment
      }
    }
  }
]] .. fragments.label

-- https://docs.github.com/en/graphql/reference/mutations#removelabelsfromlabelable
M.add_labels_mutation = [[
  mutation {
    addLabelsToLabelable(input: {labelableId: "%s", labelIds: %s}) {
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
    removeLabelsFromLabelable(input: {labelableId: "%s", labelIds: %s}) {
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
        ...LabelConnectionFragment
      }
    }
  }
]] .. fragments.label_connection .. fragments.label

M.issue_labels_query = [[
  query {
    repository(owner: "%s", name: "%s") {
      issue(number: %d) {
        labels(first: 100) {
          ...LabelConnectionFragment
        }
      }
    }
  }
]] .. fragments.label_connection .. fragments.label

M.pull_request_labels_query = [[
  query {
    repository(owner: "%s", name: "%s") {
      pullRequest(number: %d) {
        labels(first: 100) {
          ...LabelConnectionFragment
        }
      }
    }
  }
]] .. fragments.label_connection .. fragments.label

M.issue_assignees_query = [[
  query {
    repository(owner: "%s", name: "%s") {
      issue(number: %d) {
        assignees(first: 100) {
          ...AssigneeConnectionFragment
        }
      }
    }
  }
]] .. fragments.assignee_connection

M.pull_request_assignees_query = [[
  query {
    repository(owner: "%s", name: "%s") {
      pullRequest(number: %d) {
        assignees(first: 100) {
          ...AssigneeConnectionFragment
        }
      }
    }
  }
]] .. fragments.assignee_connection

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
    requestReviews(input: {pullRequestId: "%s", union: true, userIds: ["%s"]}) {
      pullRequest {
        id
        reviewRequests(first: 100) {
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
      ...ReactionGroupsUsersFragment
    }
    ... on PullRequest {
      ...ReactionGroupsUsersFragment
    }
    ... on PullRequestReviewComment {
      ...ReactionGroupsUsersFragment
    }
    ... on PullRequestReview {
      ...ReactionGroupsUsersFragment
    }
    ... on IssueComment {
      ...ReactionGroupsUsersFragment
    }
  }
}
]] .. fragments.reaction_groups_users

M.mentionable_users_query = [[
query($endCursor: String) {
  repository(owner: "%s", name: "%s") {
      mentionableUsers(first: 100, after: $endCursor) {
      pageInfo {
        endCursor
        hasNextPage
      }
      nodes {
        id
        login
        name
      }
    }
  }
}
]]

M.assignable_users_query = [[
query($endCursor: String) {
  repository(owner: "%s", name: "%s") {
    assignableUsers(first: 100, after: $endCursor) {
      pageInfo {
        endCursor
        hasNextPage
      }
      nodes {
        id
        login
        name
      }
    }
  }
}
]]

M.users_query = [[
query($endCursor: String) {
  search(query: """%s""", type: USER, first: 100) {
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
    repositories(first: 10, after: $endCursor, ownerAffiliations: [COLLABORATOR, ORGANIZATION_MEMBER, OWNER]) {
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
    createPullRequest(input: {baseRefName: "%s", headRefName: "%s", repositoryId: "%s", title: """%s""", body: """%s""", draft: %s}) {
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
        ...ReactionGroupsFragment
        projectCards(last: 20) {
          nodes {
            ...ProjectCardFragment
          }
        }
        timelineItems(first: 100) {
          ...PullRequestTimelineItemsConnectionFragment
        }
        reviewDecision
        reviewThreads(last:100) {
          nodes {
            ...ReviewThreadInformationFragment
            comments(first: 100) {
              nodes {
                ...ReviewThreadCommentFragment
              }
            }
          }
        }
        labels(first: 20) {
          ...LabelConnectionFragment
        }
        assignees(first: 20) {
          ...AssigneeConnectionFragment
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
]] .. fragments.cross_referenced_event .. fragments.issue .. fragments.pull_request .. fragments.connected_event .. fragments.milestoned_event .. fragments.demilestoned_event .. fragments.reaction_groups .. fragments.label_connection .. fragments.label .. fragments.assignee_connection .. fragments.issue_comment .. fragments.assigned_event .. fragments.labeled_event .. fragments.unlabeled_event .. fragments.closed_event .. fragments.reopened_event .. fragments.pull_request_review .. fragments.project_cards .. fragments.pull_request_commit .. fragments.review_request_removed_event .. fragments.review_requested_event .. fragments.merged_event .. fragments.review_dismissed_event .. fragments.pull_request_timeline_items_connection .. fragments.review_thread_information .. fragments.review_thread_comment .. fragments.renamed_title_event

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
      ...LabelConnectionFragment
    }
  }
}
]] .. fragments.label_connection .. fragments.label

M.open_milestones_query = [[
query($name: String!, $owner: String!, $n_milestones: Int!) {
  repository(owner: $owner, name: $name) {
    milestones(first: $n_milestones, states: [OPEN]) {
      nodes {
        id
        title
        description
        url
      }
    }
  }
}
]]

---@param query string
---@param ... string|table
---@return string
return function(query, ...)
  local opts = { escape = true }
  for _, v in ipairs { ... } do
    if type(v) == "table" then
      opts = vim.tbl_deep_extend("force", opts, v)
      break
    end
  end
  local args = {}
  for _, v in ipairs { ... } do
    table.insert(args, v)
  end
  return string.format(M[query], unpack(args))
end
