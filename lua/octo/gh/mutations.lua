local fragments = require "octo.gh.fragments"

local M = {}

-- https://docs.github.com/en/graphql/reference/mutations#addreaction
M.add_reaction = [[
mutation {
  addReaction(input: {subjectId: "%s", content: %s}) {
    subject {
      ...ReactionGroupsFragment
    }
  }
}
]] .. fragments.reaction_groups

-- https://docs.github.com/en/graphql/reference/mutations#removereaction
M.remove_reaction = [[
mutation {
  removeReaction(input: {subjectId: "%s", content: %s}) {
    subject {
      ...ReactionGroupsFragment
    }
  }
}
]] .. fragments.reaction_groups

-- https://docs.github.com/en/free-pro-team@latest/graphql/reference/mutations#resolvereviewthread
M.resolve_review_thread = [[
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
M.unresolve_review_thread = [[
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
M.start_review = [[
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
M.mark_file_as_viewed = [[
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
M.unmark_file_as_viewed = [[
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
M.submit_pull_request_review = [[
mutation {
  submitPullRequestReview(input: {pullRequestReviewId: "%s", event: %s, body: """%s"""}) {
    pullRequestReview {
      id
      state
    }
  }
}
]]

M.delete_pull_request_review = [[
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
M.add_pull_request_review_thread = [[
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
M.add_pull_request_review_multiline_thread = [[
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
M.add_issue_comment = [[
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
M.update_issue_comment = [[
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
M.update_pull_request_review_comment = [[
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
M.update_pull_request_review = [[
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
M.add_pull_request_review_comment = [[
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
M.add_pull_request_review_commit_thread = [[
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

-- M.add_pull_request_review_comment = [[
-- mutation {
--   addPullRequestReviewThreadReply(input: { pullRequestReviewThreadId: "%s", body: """%s"""}) {
--     comment{
--       id
--       body
--     }
--   }
-- }
-- ]]

-- https://docs.github.com/en/graphql/reference/mutations#deleteissuecomment
M.delete_issue_comment = [[
mutation {
  deleteIssueComment(input: {id: "%s"}) {
    clientMutationId
  }
}
]]

-- https://docs.github.com/en/graphql/reference/mutations#deletepullrequestreviewcomment
M.delete_pull_request_review_comment = [[
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
M.update_issue = [[
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
M.create_issue = [[
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

M.close_issue = [[
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
M.update_issue_state = [[
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
M.reopen_issue = [[
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
M.update_pull_request = [[
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
M.update_pull_request_state = [[
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

M.create_discussion = [[
mutation($repo_id: ID!, $category_id: ID!, $title: String!, $body: String!) {
  createDiscussion(input: {
    repositoryId: $repo_id,
    categoryId: $category_id,
    title: $title,
    body: $body
  }) {
    discussion {
      id
      url
    }
  }
}
]]

-- https://docs.github.com/en/graphql/reference/mutations#addprojectcard
M.add_project_card = [[
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
M.move_project_card = [[
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
M.delete_project_card = [[
mutation {
  deleteProjectCard(input: {cardId: "%s"}) {
    deletedCardId
  }
}
]]

-- https://docs.github.com/en/graphql/reference/mutations#addprojectv2itembyid
M.add_project_v2_item = [[
mutation {
  addProjectV2ItemById(input: {contentId: "%s", projectId: "%s"}) {
    item {
      id
    }
  }
}
]]

-- https://docs.github.com/en/graphql/reference/mutations#updateprojectv2itemfieldvalue
M.update_project_v2_item = [[
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
M.delete_project_v2_item = [[
mutation {
  deleteProjectV2Item(input: {projectId: "%s", itemId: "%s"}) {
    deletedItemId
  }
}
]]

-- https://docs.github.com/en/graphql/reference/mutations#createlabel
-- requires application/vnd.github.bane-preview+json
M.create_label = [[
mutation {
  createLabel(input: {repositoryId: "%s", name: "%s", description: """%s""", color: "%s"}) {
    label {
      ...LabelFragment
    }
  }
}
]] .. fragments.label

-- https://docs.github.com/en/graphql/reference/mutations#removelabelsfromlabelable
M.add_labels = [[
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
M.remove_labels = [[
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

-- https://docs.github.com/en/graphql/reference/mutations#addassigneestoassignable
M.add_assignees = [[
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
M.remove_assignees = [[
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
M.request_reviews = [[
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

-- https://docs.github.com/en/graphql/reference/mutations#createpullrequest
M.create_pr = [[
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

return M
