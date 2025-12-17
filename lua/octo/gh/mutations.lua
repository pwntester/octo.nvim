local fragments = require "octo.gh.fragments"
local config = require "octo.config"

local M = {}

M.setup = function()
  -- https://docs.github.com/en/graphql/reference/mutations#addreaction
  -- inject: graphql
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
  ---@class octo.mutations.StartReview
  ---@field data {
  ---  addPullRequestReview: {
  ---    pullRequestReview: {
  ---      id: string,
  ---      state: string,
  ---      pullRequest: {
  ---        reviewThreads: {
  ---          nodes: octo.ReviewThread[],
  ---        },
  ---      },
  ---    },
  ---  },
  ---}

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
mutation($path: String!, $pullRequestId: ID!) {
  markFileAsViewed(input: {path: $path, pullRequestId: $pullRequestId}) {
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
mutation($path: String!, $pullRequestId: ID!) {
  unmarkFileAsViewed(input: {path: $path, pullRequestId: $pullRequestId}) {
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

  ---@alias DiffSide "LEFT" | "RIGHT"

  ---https://docs.github.com/en/graphql/reference/input-objects#addpullrequestreviewthreadinput
  ---@class octo.mutations.AddPullRequestReviewThreadInput
  ---@field pullRequestReviewId string
  ---@field body string
  ---@field path string?
  ---@field startSide DiffSide?
  ---@field side DiffSide?
  ---@field startLine integer?
  ---@field line integer?

  -- https://docs.github.com/en/graphql/reference/mutations#addpullrequestreviewthread
  M.add_pull_request_review_thread = [[
mutation($input: AddPullRequestReviewThreadInput!) {
  addPullRequestReviewThread(input: $input) {
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

  ---@class octo.mutations.AddPullRequestReviewThread
  ---@field thread {
  ---   id: string,
  ---   comments: {
  ---     nodes: {
  ---       id: string,
  ---       body: string,
  ---       diffHunk: string,
  ---       createdAt: string,
  ---       lastEditedAt: string,
  ---       commit: {
  ---         oid: string,
  ---         abbreviatedOid: string,
  ---       },
  ---       author: {
  ---         login: string,
  ---       },
  ---       authorAssociation: string,
  ---       viewerDidAuthor: boolean,
  ---       viewerCanUpdate: boolean,
  ---       viewerCanDelete: boolean,
  ---       state: string,
  ---       url: string,
  ---       replyTo: {
  ---         id: string,
  ---         url: string,
  ---       },
  ---       pullRequest: {
  ---         reviewThreads: {
  ---           nodes: octo.ReviewThread[],
  ---         },
  ---       },
  ---       path: string,
  ---     }[],
  ---   },
  ---   pullRequest: {
  ---     reviewThreads: {
  ---       nodes: octo.ReviewThread[],
  ---     },
  ---   },
  --- }

  ---@class octo.mutations.AddIssueComment
  ---@field data {
  ---  addComment: {
  ---    commentEdge: {
  ---      node: {
  ---        id: string,
  ---        body: string,
  ---      },
  ---    },
  ---  },
  ---}

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
  ---@class octo.mutations.UpdateIssueComment
  ---@field data {
  ---  updateIssueComment: {
  ---    issueComment: {
  ---      id: string,
  ---      body: string,
  ---    },
  ---  },
  ---}j

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
  ---@class octo.mutations.UpdateDiscussionComment
  ---@field data {
  ---  updateDiscussionComment: {
  ---    comment: {
  ---      id: string,
  ---      body: string,
  ---    },
  ---  },
  ---}

  --- https://docs.github.com/en/graphql/guides/using-the-graphql-api-for-discussions#updatediscussioncomment
  M.update_discussion_comment = [[
mutation {
  updateDiscussionComment(input: {commentId: "%s", body: """%s"""}) {
    comment {
      id
      body
    }
  }
}
]]
  ---@class octo.mutations.UpdatePullRequestReviewComment
  ---@field data {
  ---  updatePullRequestReviewComment: {
  ---    pullRequestReviewComment: {
  ---      id: string,
  ---      body: string,
  ---      pullRequest: {
  ---        reviewThreads: {
  ---          nodes: octo.ReviewThread[],
  ---        },
  ---      },
  ---    },
  ---  },
  ---}

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
  ---@class octo.mutations.UpdateDiscussion
  ---@field data {
  ---  updateDiscussion: {
  ---    discussion: {
  ---      id: string,
  ---      title: string,
  ---      body: string,
  ---    },
  ---  },
  ---}

  ---https://docs.github.com/en/graphql/reference/input-objects#updatediscussioninput
  ---@class octo.mutations.UpdateDiscussionInput
  ---@field discussionId string
  ---@field title string?
  ---@field body string?
  ---@field categoryId string?

  M.update_discussion = [[
mutation($input: UpdateDiscussionInput!) {
  updateDiscussion(input: $input) {
    discussion {
      id
      title
      body
    }
  }
}
]]

  M.add_discussion_comment = [[
mutation($discussion_id: ID!, $body: String!, $reply_to_id: ID) {
  addDiscussionComment(input: {
    discussionId: $discussion_id,
    body: $body
    replyToId: $reply_to_id
  }) {
    comment {
      id
      body
    }
  }
}
]]
  ---@class octo.mutations.UpdatePullRequestReview
  ---@field data {
  ---  updatePullRequestReview: {
  ---    pullRequestReview: {
  ---      id: string,
  ---      state: string,
  ---      body: string,
  ---    },
  ---  },
  ---}

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
  ---@class octo.mutations.AddPullRequestReviewComment
  ---@field data {
  ---  addPullRequestReviewComment: {
  ---    comment: {
  ---      id: string,
  ---      body: string,
  ---      pullRequest: {
  ---        reviewThreads: {
  ---          nodes: octo.ReviewThread[],
  ---        },
  ---      },
  ---    },
  ---  },
  ---}

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
  ---@class octo.mutations.AddPullRequestReviewCommitThread
  ---@field data {
  ---  addPullRequestReviewComment: {
  ---    comment: {
  ---      id: string,
  ---      body: string,
  ---      pullRequest: {
  ---        reviewThreads: {
  ---          nodes: octo.ReviewThread[],
  ---        },
  ---      },
  ---    },
  ---  },
  ---}

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

  M.delete_discussion_comment = [[
mutation {
  deleteDiscussionComment(input: {id: "%s"}) {
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
  ---@class octo.mutations.UpdateIssue
  ---@field data {
  ---  updateIssue: {
  ---    issue: {
  ---      id: string,
  ---      number: integer,
  ---      state: string,
  ---      title: string,
  ---      body: string,
  ---      repository: {
  ---        nameWithOwner: string,
  ---      },
  ---    },
  ---  },
  ---}

  ---https://docs.github.com/en/graphql/reference/input-objects#updateissueinput
  ---@class octo.mutations.UpdateIssueInput
  ---@field id string
  ---@field title string?
  ---@field body string?

  -- https://docs.github.com/en/free-pro-team@latest/graphql/reference/mutations#updateissue
  M.update_issue = [[
mutation($input: UpdateIssueInput!) {
  updateIssue(input: $input) {
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

  ---https://docs.github.com/en/graphql/reference/input-objects#createissueinput
  ---@class octo.mutations.CreateIssueInput
  ---@field repositoryId string
  ---@field title string
  ---@field body string?

  -- https://docs.github.com/en/free-pro-team@latest/graphql/reference/mutations#createissue
  M.create_issue = [[
mutation($input: CreateIssueInput!) {
  createIssue(input: $input) {
    issue {
      ...IssueInformationFragment
      participants(first:10) {
        nodes {
          login
        }
      }
      ...ReactionGroupsFragment
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
]] .. fragments.cross_referenced_event .. fragments.issue .. fragments.pull_request .. fragments.connected_event .. fragments.milestoned_event .. fragments.demilestoned_event .. fragments.reaction_groups .. fragments.label_connection .. fragments.label .. fragments.assignee_connection .. fragments.issue_comment .. fragments.assigned_event .. fragments.unassigned_event .. fragments.labeled_event .. fragments.unlabeled_event .. fragments.closed_event .. fragments.reopened_event .. fragments.issue_timeline_items_connection .. fragments.renamed_title_event .. fragments.issue_information .. fragments.referenced_event .. fragments.pinned_event .. fragments.unpinned_event .. fragments.subissue_added_event .. fragments.subissue_removed_event .. fragments.parent_issue_added_event .. fragments.parent_issue_removed_event .. fragments.issue_type_added_event .. fragments.issue_type_removed_event .. fragments.issue_type_changed_event .. fragments.comment_deleted_event .. fragments.blocked_by_added_event .. fragments.blocked_by_removed_event .. fragments.blocking_added_event .. fragments.blocking_removed_event .. fragments.transferred_event

  if config.values.default_to_projects_v2 then
    M.create_issue = M.create_issue
      .. fragments.added_to_project_v2_event
      .. fragments.project_v2_item_status_changed_event
      .. fragments.removed_from_project_v2_event
  end

  M.close_issue = [[
mutation($issueId: ID!, $stateReason: IssueCloseReason) {
  closeIssue(input: {issueId: $issueId, stateReason: $stateReason}) {
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
]] .. fragments.cross_referenced_event .. fragments.issue .. fragments.pull_request .. fragments.connected_event .. fragments.milestoned_event .. fragments.demilestoned_event .. fragments.label_connection .. fragments.label .. fragments.reaction_groups .. fragments.assignee_connection .. fragments.issue_comment .. fragments.assigned_event .. fragments.unassigned_event .. fragments.labeled_event .. fragments.unlabeled_event .. fragments.closed_event .. fragments.reopened_event .. fragments.issue_timeline_items_connection .. fragments.issue_information .. fragments.renamed_title_event .. fragments.referenced_event .. fragments.pinned_event .. fragments.unpinned_event .. fragments.subissue_added_event .. fragments.subissue_removed_event .. fragments.parent_issue_added_event .. fragments.parent_issue_removed_event .. fragments.issue_type_added_event .. fragments.issue_type_removed_event .. fragments.issue_type_changed_event .. fragments.comment_deleted_event .. fragments.blocked_by_added_event .. fragments.blocked_by_removed_event .. fragments.blocking_added_event .. fragments.blocking_removed_event .. fragments.transferred_event

  if config.values.default_to_projects_v2 then
    M.close_issue = M.close_issue
      .. fragments.added_to_project_v2_event
      .. fragments.project_v2_item_status_changed_event
      .. fragments.removed_from_project_v2_event
  end

  -- https://docs.github.com/en/free-pro-team@latest/graphql/reference/mutations#updateissue
  M.update_issue_state = [[
mutation($id: ID!, $state: IssueState!) {
  updateIssue(input: {id: $id, state: $state}) {
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
]] .. fragments.cross_referenced_event .. fragments.issue .. fragments.pull_request .. fragments.connected_event .. fragments.milestoned_event .. fragments.demilestoned_event .. fragments.reaction_groups .. fragments.label_connection .. fragments.label .. fragments.assignee_connection .. fragments.issue_comment .. fragments.assigned_event .. fragments.unassigned_event .. fragments.labeled_event .. fragments.unlabeled_event .. fragments.closed_event .. fragments.reopened_event .. fragments.issue_timeline_items_connection .. fragments.issue_information .. fragments.renamed_title_event .. fragments.referenced_event .. fragments.pinned_event .. fragments.unpinned_event .. fragments.subissue_added_event .. fragments.subissue_removed_event .. fragments.parent_issue_added_event .. fragments.parent_issue_removed_event .. fragments.issue_type_added_event .. fragments.issue_type_removed_event .. fragments.issue_type_changed_event .. fragments.comment_deleted_event .. fragments.blocked_by_added_event .. fragments.blocked_by_removed_event .. fragments.blocking_added_event .. fragments.blocking_removed_event .. fragments.transferred_event

  if config.values.default_to_projects_v2 then
    M.update_issue_state = M.update_issue_state
      .. fragments.added_to_project_v2_event
      .. fragments.project_v2_item_status_changed_event
      .. fragments.removed_from_project_v2_event
  end

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
]] .. fragments.cross_referenced_event .. fragments.issue .. fragments.pull_request .. fragments.connected_event .. fragments.milestoned_event .. fragments.demilestoned_event .. fragments.reaction_groups .. fragments.label_connection .. fragments.label .. fragments.assignee_connection .. fragments.issue_comment .. fragments.assigned_event .. fragments.unassigned_event .. fragments.labeled_event .. fragments.unlabeled_event .. fragments.closed_event .. fragments.reopened_event .. fragments.issue_timeline_items_connection .. fragments.issue_information .. fragments.renamed_title_event .. fragments.referenced_event .. fragments.pinned_event .. fragments.unpinned_event .. fragments.subissue_added_event .. fragments.subissue_removed_event .. fragments.parent_issue_added_event .. fragments.parent_issue_removed_event .. fragments.issue_type_added_event .. fragments.issue_type_removed_event .. fragments.issue_type_changed_event .. fragments.comment_deleted_event .. fragments.blocked_by_added_event .. fragments.blocked_by_removed_event .. fragments.blocking_added_event .. fragments.blocking_removed_event .. fragments.transferred_event

  if config.values.default_to_projects_v2 then
    M.reopen_issue = M.reopen_issue
      .. fragments.added_to_project_v2_event
      .. fragments.project_v2_item_status_changed_event
      .. fragments.removed_from_project_v2_event
  end

  ---@class octo.mutations.UpdatePullRequest
  ---@field data {
  ---  updatePullRequest: {
  ---    pullRequest: {
  ---      id: string,
  ---      number: integer,
  ---      state: string,
  ---      title: string,
  ---      body: string,
  ---    },
  ---  },
  ---}

  ---https://docs.github.com/en/graphql/reference/input-objects#updatepullrequestinput
  ---@class octo.mutations.UpdatePullRequestInput
  ---@field pullRequestId string
  ---@field title string?
  ---@field body string?

  -- https://docs.github.com/en/free-pro-team@latest/graphql/reference/mutations#updatepullrequest
  M.update_pull_request = [[
mutation($input: UpdatePullRequestInput!) {
  updatePullRequest(input: $input) {
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
mutation($pullRequestId: ID!, $state: PullRequestUpdateState!) {
  updatePullRequest(input: {pullRequestId: $pullRequestId, state: $state}) {
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
]] .. fragments.cross_referenced_event .. fragments.issue .. fragments.pull_request .. fragments.connected_event .. fragments.convert_to_draft_event .. fragments.milestoned_event .. fragments.demilestoned_event .. fragments.reaction_groups .. fragments.label_connection .. fragments.label .. fragments.assignee_connection .. fragments.issue_comment .. fragments.assigned_event .. fragments.unassigned_event .. fragments.labeled_event .. fragments.unlabeled_event .. fragments.closed_event .. fragments.ready_for_review_event .. fragments.reopened_event .. fragments.pull_request_review .. fragments.pull_request_commit .. fragments.review_request_removed_event .. fragments.merged_event .. fragments.review_requested_event .. fragments.renamed_title_event .. fragments.review_dismissed_event .. fragments.pull_request_timeline_items_connection .. fragments.deployed_event .. fragments.head_ref_deleted_event .. fragments.head_ref_restored_event .. fragments.head_ref_force_pushed_event .. fragments.auto_squash_enabled_event .. fragments.automatic_base_change_succeeded_event .. fragments.base_ref_changed_event .. fragments.comment_deleted_event

  if config.values.default_to_projects_v2 then
    M.update_pull_request_state = M.update_pull_request_state
      .. fragments.added_to_project_v2_event
      .. fragments.removed_from_project_v2_event
      .. fragments.project_v2_item_status_changed_event
  end

  M.create_discussion = [[
mutation($repo_id: ID!, $category_id: ID!, $title: String!, $body: String!) {
  createDiscussion(input: {
    repositoryId: $repo_id,
    categoryId: $category_id,
    title: $title,
    body: $body
  }) {
      discussion {
        ...DiscussionDetailsFragment
        labels(first: 20) {
          ...LabelConnectionFragment
        }
        comments(first: 25) {
          totalCount
          nodes {
            ...DiscussionCommentFragment
            replies(first: 15) {
              totalCount
              nodes {
                ...DiscussionCommentFragment
              }
            }
          }
        }
      }
    }
  }
]] .. fragments.reaction_groups .. fragments.label_connection .. fragments.label .. fragments.discussion_info .. fragments.discussion_details .. fragments.discussion_comment

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
      ... on Discussion {
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
      ... on Discussion {
        id
      }
    }
  }
}
]]

  -- https://docs.github.com/en/graphql/reference/mutations#addassigneestoassignable
  M.add_assignees = [[
mutation($object_id: ID!, $user_ids: [ID!]!) {
  addAssigneesToAssignable(input: {assignableId: $object_id, assigneeIds: $user_ids}) {
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
mutation($object_id: ID!, $user_ids: [ID!]!) {
  requestReviews(input: {pullRequestId: $object_id, union: true, userIds: $user_ids}) {
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

  ---https://docs.github.com/en/graphql/reference/input-objects#createpullrequestinput
  ---@class octo.mutations.CreatePullRequestInput
  ---@field baseRefName string
  ---@field headRefName string
  ---@field repositoryId string
  ---@field title string
  ---@field body string
  ---@field draft boolean

  -- https://docs.github.com/en/graphql/reference/mutations#createpullrequest
  M.create_pr = [[
mutation($input: CreatePullRequestInput!) {
  createPullRequest(input: $input) {
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
]] .. fragments.cross_referenced_event .. fragments.issue .. fragments.pull_request .. fragments.connected_event .. fragments.convert_to_draft_event .. fragments.milestoned_event .. fragments.demilestoned_event .. fragments.reaction_groups .. fragments.label_connection .. fragments.label .. fragments.assignee_connection .. fragments.issue_comment .. fragments.assigned_event .. fragments.unassigned_event .. fragments.labeled_event .. fragments.unlabeled_event .. fragments.closed_event .. fragments.ready_for_review_event .. fragments.reopened_event .. fragments.pull_request_review .. fragments.pull_request_commit .. fragments.review_request_removed_event .. fragments.review_requested_event .. fragments.merged_event .. fragments.review_dismissed_event .. fragments.pull_request_timeline_items_connection .. fragments.review_thread_information .. fragments.review_thread_comment .. fragments.renamed_title_event .. fragments.deployed_event .. fragments.head_ref_deleted_event .. fragments.head_ref_restored_event .. fragments.head_ref_force_pushed_event .. fragments.auto_squash_enabled_event .. fragments.automatic_base_change_succeeded_event .. fragments.base_ref_changed_event .. fragments.comment_deleted_event

  if config.values.default_to_projects_v2 then
    M.create_pr = M.create_pr
      .. fragments.added_to_project_v2_event
      .. fragments.removed_from_project_v2_event
      .. fragments.project_v2_item_status_changed_event
  end

  M.mark_answer = [[
mutation($id: ID!) {
  markDiscussionCommentAsAnswer(input: {id: $id}) {
    clientMutationId
  }
}
]]

  M.unmark_answer = [[
mutation($id: ID!) {
  unmarkDiscussionCommentAsAnswer(input: {id: $id}) {
    clientMutationId
  }
}
]]

  M.pin_issue = [[
mutation($issue_id: ID!) {
  pinIssue(input: {issueId: $issue_id}) {
    issue {
      id
    }
  }
}
]]

  M.unpin_issue = [[
mutation($issue_id: ID!) {
  unpinIssue(input: {issueId: $issue_id}) {
    issue {
      id
    }
  }
}
]]

  M.close_discussion = [[
mutation($discussion_id: ID!, $reason: DiscussionCloseReason) {
  closeDiscussion(input: {discussionId: $discussion_id, reason: $reason}) {
    discussion {
      id
    }
  }
}
]]

  M.reopen_discussion = [[
mutation($discussion_id: ID!) {
  reopenDiscussion(input: {discussionId: $discussion_id}) {
    discussion {
      id
    }
  }
}
]]

  M.add_subissue = [[
mutation($parent_id: ID!, $child_id: ID!) {
  addSubIssue(input: {issueId: $parent_id, subIssueId: $child_id}) {
    issue {
      id
    }
    subIssue {
      id
    }
  }
}
]]

  M.remove_subissue = [[
mutation($parent_id: ID!, $child_id: ID!) {
  removeSubIssue(input: {issueId: $parent_id, subIssueId: $child_id}) {
    issue {
      id
    }
    subIssue {
      id
    }
  }
}
]]

  M.update_issue_issue_type = [[
mutation($issue_id: ID!, $issue_type_id: ID) {
  updateIssueIssueType(input: {issueId: $issue_id, issueTypeId: $issue_type_id}) {
    issue {
      id
      issueType {
        id
        name
      }
    }
  }
}
]]
  M.star_repo = [[
  mutation($repo_id: ID!) {
    addStar(input: {starrableId: $repo_id}) {
      starrable {
        id
        viewerHasStarred
      }
    }
  }
  ]]
  M.unstar_repo = [[
  mutation($repo_id: ID!) {
    removeStar(input: {starrableId: $repo_id}) {
      starrable {
        id
        viewerHasStarred
      }
    }
  }
  ]]
  ---@class octo.mutations.UpdateSubscription
  ---@field data {
  ---  updateSubscription: {
  ---    subscribable: {
  ---      id: string,
  ---      viewerSubscription: octo.SubscriptionState,
  ---    },
  ---  },
  ---}

  ---@class octo.mutations.UpdateSubscriptionInput
  ---@field subscribable_id string
  ---@field state octo.SubscriptionState

  -- https://docs.github.com/en/graphql/reference/mutations#updatesubscription
  M.update_subscription = [[
  mutation($subscribable_id: ID!, $state: SubscriptionState!) {
    updateSubscription(input: {subscribableId: $subscribable_id, state: $state}) {
      subscribable {
        id
        viewerSubscription
      }
    }
  }
  ]]

  M.delete_branch = [[
  mutation($branchRef: ID!) {
    deleteRef(input: {refId: $branchRef}) {
      clientMutationId
    }
  }
  ]]
end

return M
