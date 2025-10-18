local fragments = require "octo.gh.fragments"

local M = {}

---@class octo.queries.PendingReviewThreads
---@field data {
---  repository: {
---    pullRequest: {
---      reviews: {
---        nodes: {
---          id: string,
---          viewerDidAuthor: boolean,
---        }[],
---      },
---      reviewThreads: {
---        nodes: octo.ReviewThread[],
---      },
---    },
---  },
---}

-- https://docs.github.com/en/graphql/reference/objects#pullrequestreviewthread
M.pending_review_threads = [[
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

---@class octo.ReviewThread : octo.ReviewThreadInformationFragment
--- @field comments {
---   nodes: octo.ReviewThreadCommentFragment[],
---   pageInfo: {
---     hasNextPage: boolean,
---     endCursor: string,
---   },
--- }

---@class octo.queries.ReviewThreads
---@field data {
---  repository: {
---    pullRequest: {
---      reviewThreads: {
---        nodes: octo.ReviewThread[],
---      },
---    },
---  },
---}

-- https://docs.github.com/en/free-pro-team@latest/graphql/reference/objects#pullrequestreviewthread
M.review_threads = [[
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

---@class octo.PullRequestTimelineItemsConnection : octo.fragments.PullRequestTimelineItemsConnection
---@field pageInfo { hasNextPage: boolean, endCursor: string }

---@class octo.PullRequest : octo.ReactionGroupsFragment
---@field id string
---@field isDraft boolean
---@field number integer
---@field state string
---@field title string
---@field body string
---@field createdAt string
---@field closedAt string
---@field updatedAt string
---@field url string
---@field headRepository { nameWithOwner: string }
---@field files { nodes: { path: string, viewerViewedState: ViewedState }[] }
---@field merged boolean
---@field mergedBy { name: string }|{ login: string }|{ login: string, isViewer: boolean }
---@field participants { nodes: { login: string }[] }
---@field additions integer
---@field deletions integer
---@field commits { totalCount: integer }
---@field changedFiles integer
---@field headRefName string
---@field headRefOid string
---@field baseRefName string
---@field baseRefOid string
---@field baseRepository { name: string, nameWithOwner: string }
---@field milestone { title: string, state: string }
---@field author { login: string }
---@field authorAssociation string
---@field viewerDidAuthor boolean
---@field viewerCanUpdate boolean
---@field projectItems? octo.fragments.ProjectsV2Connection
---@field timelineItems octo.PullRequestTimelineItemsConnection
---@field reviewDecision string
---@field reviewThreads { nodes: octo.ReviewThread[] }
---@field labels octo.fragments.LabelConnection
---@field assignees octo.fragments.AssigneeConnection
---@field reviewRequests { totalCount: integer, nodes: { requestedReviewer: { name: string }|{ login: string }|{ login: string, isViewer: boolean } }[] }
---@field statusCheckRollup { state: string }
---@field mergeStateStatus string
---@field mergeable string
---@field autoMergeRequest { enabledBy: { login: string }, mergeMethod: string }

-- https://docs.github.com/en/free-pro-team@latest/graphql/reference/objects#pullrequest
M.pull_request = [[
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
      authorAssociation
      viewerDidAuthor
      viewerCanUpdate
      ...ReactionGroupsFragment
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
]] .. fragments.cross_referenced_event .. fragments.issue .. fragments.pull_request .. fragments.connected_event .. fragments.convert_to_draft_event .. fragments.milestoned_event .. fragments.demilestoned_event .. fragments.reaction_groups .. fragments.label_connection .. fragments.label .. fragments.assignee_connection .. fragments.issue_comment .. fragments.assigned_event .. fragments.labeled_event .. fragments.unlabeled_event .. fragments.closed_event .. fragments.ready_for_review_event .. fragments.reopened_event .. fragments.pull_request_review .. fragments.pull_request_commit .. fragments.review_request_removed_event .. fragments.review_requested_event .. fragments.merged_event .. fragments.renamed_title_event .. fragments.review_dismissed_event .. fragments.pull_request_timeline_items_connection .. fragments.review_thread_information .. fragments.review_thread_comment
---@class octo.IssueTimelineItemConnection : octo.fragments.IssueTimelineItemsConnection
--- @field pageInfo { hasNextPage: boolean, endCursor: string }

---@class octo.Issue : octo.fragments.IssueInformation, octo.ReactionGroupsFragment
---@field participants { nodes: { login: string }[] }
---@field parent octo.fragments.Issue
---@field projectItems? octo.fragments.ProjectsV2Connection
---@field timelineItems octo.IssueTimelineItemConnection
---@field labels octo.fragments.LabelConnection
---@field assignees octo.fragments.AssigneeConnection

-- https://docs.github.com/en/free-pro-team@latest/graphql/reference/objects#issue
M.issue = [[
query($endCursor: String) {
  repository(owner: "%s", name: "%s") {
    issue(number: %d) {
      ...IssueInformationFragment
      participants(first:10) {
        nodes {
          login
        }
      }
      parent {
        ...IssueFields
      }
      ...ReactionGroupsFragment
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
]] .. fragments.cross_referenced_event .. fragments.issue .. fragments.pull_request .. fragments.connected_event .. fragments.milestoned_event .. fragments.demilestoned_event .. fragments.reaction_groups .. fragments.label .. fragments.label_connection .. fragments.assignee_connection .. fragments.issue_comment .. fragments.assigned_event .. fragments.labeled_event .. fragments.unlabeled_event .. fragments.closed_event .. fragments.reopened_event .. fragments.renamed_title_event .. fragments.issue_timeline_items_connection .. fragments.issue_information .. fragments.referenced_event .. fragments.pinned_event .. fragments.unpinned_event .. fragments.subissue_added_event .. fragments.subissue_removed_event .. fragments.parent_issue_added_event .. fragments.parent_issue_removed_event .. fragments.issue_type_added_event .. fragments.issue_type_removed_event .. fragments.issue_type_changed_event

-- https://docs.github.com/en/graphql/reference/unions#issueorpullrequest
M.issue_kind = [[
query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    issueOrPullRequest(number: $number) {
      __typename
    }
  }
}
]]

---@class octo.DiscussionSummary : octo.fragments.DiscussionInfo
---@field createdAt string
---@field body string
---@field labels octo.fragments.LabelConnection

M.discussion_summary = [[
query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    discussion(number: $number) {
      ...DiscussionInfoFragment
      createdAt
      body
      labels(first: 20) {
        ...LabelConnectionFragment
      }
    }
  }
}
]] .. fragments.discussion_info .. fragments.label_connection .. fragments.label
---@class octo.PullRequestSummary
---@field __typename "PullRequest"
---@field headRefName string
---@field baseRefName string
---@field createdAt string
---@field state string
---@field number integer
---@field title string
---@field body string
---@field repository { nameWithOwner: string }
---@field author { login: string }
---@field authorAssociation string
---@field labels octo.fragments.LabelConnection

---@class octo.IssueSummary
---@field __typename "Issue"
---@field createdAt string
---@field state string
---@field stateReason string
---@field number integer
---@field title string
---@field body string
---@field repository { nameWithOwner: string }
---@field author { login: string }
---@field authorAssociation string
---@field labels octo.fragments.LabelConnection

---@alias octo.IssueOrPullRequestSummary octo.PullRequestSummary|octo.IssueSummary

-- https://docs.github.com/en/graphql/reference/unions#issueorpullrequest
M.issue_summary = [[
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
M.repository_id = [[
query($owner: String!, $name: String!) {
  repository(owner: $owner, name: $name) {
    id
  }
}
]]

---@class octo.queries.RepositoryTemplates.data.repository
---@field issueTemplates { body: string, about: string, name: string, title: string }[]
---@field pullRequestTemplates { body: string, filename: string }[]

-- https://docs.github.com/en/free-pro-team@latest/graphql/reference/objects#repository
-- https://docs.github.com/en/graphql/reference/objects#issuetemplate
-- https://docs.github.com/en/graphql/reference/objects#pullrequesttemplate
M.repository_templates = [[
query($owner: String!, $name: String!) {
  repository(owner: $owner, name: $name) {
    issueTemplates { body about name title  }
    pullRequestTemplates { body filename }
  }
}
]]

-- https://docs.github.com/en/free-pro-team@latest/graphql/reference/objects#issue
-- https://docs.github.com/en/free-pro-team@latest/graphql/reference/input-objects#issueorder
-- https://docs.github.com/en/free-pro-team@latest/graphql/reference/input-objects#issuefilters
-- filter eg: labels: ["help wanted", "bug"]
M.issues = [[
query($endCursor: String) {
  repository(owner: "%s", name: "%s") {
    issues(first: 100, after: $endCursor, filterBy: {%s}, orderBy: {field: %s, direction: %s}) {
      nodes {
        __typename
        id
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
M.pull_requests = [[
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

M.search_count = [[
query($prompt: String!, $type: SearchType = ISSUE) {
  search(query: $prompt, type: $type, last: 100) {
    issueCount
  }
}
]]

M.search = [[
query($prompt: String!, $type: SearchType = ISSUE, $last: Int = 100) {
  search(query: $prompt, type: $type, last: $last) {
    nodes {
      ... on Issue {
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
      ... on Discussion {
        __typename
        category {
          name
        }
        ...DiscussionInfoFragment
      }
      ... on Repository {
        __typename
        ...RepositoryFragment
      }
      ... on Organization {
        __typename
        login
        name
        url
      }
      ... on User {
        __typename
        login
      }
    }
  }
}
]] .. fragments.discussion_info .. fragments.repository

M.discussions = [[
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

M.discussion_categories = [[
query($owner: String!, $name: String!) {
  repository(owner: $owner, name: $name) {
    discussionCategories(first: 20) {
      nodes {
        id
        name
        emoji
      }
    }
  }
}
]]
---@class octo.DiscussionComment : octo.fragments.DiscussionComment
---@field replies {
---  totalCount: integer,
---  nodes: octo.fragments.DiscussionComment[],
---  pageInfo: {
---    hasNextPage: boolean,
---    endCursor: string,
---  },
---}

---@class octo.Discussion : octo.fragments.DiscussionDetails
---@field labels octo.fragments.LabelConnection
---@field comments {
---  totalCount: integer,
---  nodes: octo.DiscussionComment[],
---}

M.discussion = [[
query($owner: String!, $name: String!, $number: Int!, $endCursor: String) {
  repository(owner: $owner, name: $name) {
    discussion(number: $number) {
      ...DiscussionDetailsFragment
      labels(first: 20) {
        ...LabelConnectionFragment
      }
      comments(first: 25, after: $endCursor) {
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
        pageInfo {
          hasNextPage
          endCursor
        }
      }
    }
  }
}
]] .. fragments.reaction_groups .. fragments.label_connection .. fragments.label .. fragments.discussion_info .. fragments.discussion_details .. fragments.discussion_comment

---@class octo.Release : octo.ReactionGroupsFragment
--- @field id string
--- @field name string
--- @field tagName string
--- @field tagCommit { abbreviatedOid: string }
--- @field url string
--- @field isPrerelease boolean
--- @field isLatest boolean
--- @field publishedAt string
--- @field description string
--- @field author { login: string }
--- @field releaseAssets {
---   nodes: {
---     name: string,
---     downloadUrl: string,
---     downloadCount: number,
---     size: number,
---     updatedAt: string,
---   }[] }

M.release = [[
query($owner: String!, $name: String!, $tag: String!) {
  repository(owner: $owner, name: $name) {
    release(tagName: $tag) {
      id
      name
      tagName
      tagCommit {
        abbreviatedOid
      }
      url
      isPrerelease
      isLatest
      publishedAt
      description
      releaseAssets(first: 100) {
        nodes {
          name
          downloadUrl
          downloadCount
          size
          updatedAt
        }
      }
      author {
        login
      }
      ...ReactionGroupsFragment
    }
  }
}
]] .. fragments.reaction_groups

-- https://docs.github.com/en/graphql/reference/objects#projectv2
M.projects_v2 = [[
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

-- https://docs.github.com/en/graphql/reference/objects#label
M.labels = [[
query {
  repository(owner: "%s", name: "%s") {
    labels(first: 100) {
      ...LabelConnectionFragment
    }
  }
}
]] .. fragments.label_connection .. fragments.label

M.issue_labels = [[
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

M.discussion_labels = [[
query {
  repository(owner: "%s", name: "%s") {
    discussion(number: %d) {
      labels(first: 100) {
        ...LabelConnectionFragment
      }
    }
  }
}
]] .. fragments.label_connection .. fragments.label

M.pull_request_labels = [[
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

M.pull_request_reviewers = [[
query {
  repository(owner: "%s", name: "%s") {
    pullRequest(number: %d) {
      reviewRequests(first: 100) {
        totalCount
        nodes {
          requestedReviewer {
            ... on User {
              id
              login
              name
            }
            ... on Mannequin {
              id
              login
            }
            ... on Team {
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

M.issue_assignees = [[
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

M.pull_request_assignees = [[
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
---@class octo.UserProfile
---@field login string
---@field bio string
---@field company string
---@field followers { totalCount: integer }
---@field following { totalCount: integer }
---@field hovercard { contexts: { message: string }[] }
---@field hasSponsorsListing boolean
---@field isEmployee boolean
---@field isViewer boolean
---@field location string
---@field organizations { nodes: { name: string }[] }
---@field name string
---@field status { emoji: string, message: string }
---@field twitterUsername string
---@field websiteUrl string

---@class octo.queries.UserProfile
---@field data {
---  user: octo.UserProfile,
---}

M.user_profile = [[
query($login: String!) {
  user(login: $login) {
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

M.changed_files = [[
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

M.file_content = [[
query($owner: String!, $name: String!, $expression: String!) {
  repository(owner: $owner, name: $name) {
    object(expression: $expression) {
      ... on Blob {
        text
      }
    }
  }
}
]]

M.directory_file_content = [[
query($owner: String!, $name: String!, $expression: String!) {
  repository(owner: $owner, name: $name) {
    object(expression: $expression) {
      ... on Tree {
        entries {
          name
          object {
            ... on Blob {
              text
            }
          }
        }
      }
    }
  }
}
]]

---@class octo.queries.ReactionsForObject
---@field data {
---  node: octo.fragments.ReactionGroupsUsers,
---}

M.reactions_for_object = [[
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
    ... on Discussion {
      ...ReactionGroupsUsersFragment
    }
    ... on DiscussionComment {
      ...ReactionGroupsUsersFragment
    }
  }
}
]] .. fragments.reaction_groups_users

M.mentionable_users = [[
query($owner: String!, $name: String!, $endCursor: String) {
  repository(owner: $owner, name: $name) {
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

M.assignable_users = [[
query($owner: String!, $name: String! $endCursor: String) {
  repository(owner: $owner, name: $name) {
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

M.users = [[
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

M.repos = [[
query($login: String!, $endCursor: String) {
  repositoryOwner(login: $login) {
    repositories(first: 10, after: $endCursor, ownerAffiliations: [COLLABORATOR, ORGANIZATION_MEMBER, OWNER]) {
      nodes {
        ...RepositoryFragment
      }
      pageInfo {
        hasNextPage
        endCursor
      }
    }
  }
}
]] .. fragments.repository
---@class octo.Repository : octo.fragments.Repository
---@field pushedAt string
---@field defaultBranchRef { name: string }
---@field securityPolicyUrl string
---@field isLocked boolean
---@field lockReason string
---@field isMirror boolean
---@field mirrorUrl string
---@field hasProjectsEnabled boolean
---@field hasDiscussionsEnabled boolean
---@field projectsUrl string
---@field homepageUrl string
---@field primaryLanguage { name: string, color: string }
---@field refs { nodes: { name: string }[] }
---@field languages { nodes: { name: string, color: string }[] }

M.repository = [[
query($owner: String!, $name: String!) {
  repository(owner: $owner, name: $name) {
    ...RepositoryFragment
    pushedAt
    defaultBranchRef {
      name
    }
    securityPolicyUrl
    isLocked
    lockReason
    isMirror
    mirrorUrl
    hasProjectsEnabled
    hasDiscussionsEnabled
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
]] .. fragments.repository

M.gists = [[
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

-- https://docs.github.com/en/graphql/reference/queries#user
M.user = [[
query($login: String!) {
  user(login: $login) {
    id
  }
}
]]

-- https://docs.github.com/en/graphql/reference/objects#pullrequestreviewthread
M.repo_labels = [[
query($owner: String!, $name: String!) {
  repository(owner: $owner, name: $name) {
    labels(first: 100) {
      ...LabelConnectionFragment
    }
  }
}
]] .. fragments.label_connection .. fragments.label

M.open_milestones = [[
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

M.comment_url = [[
query($id: ID!) {
  node(id: $id) {
    ... on IssueComment {
      url
    }
    ... on PullRequestReviewComment {
      url
    }
    ... on PullRequestReview {
      url
    }
    ... on DiscussionComment {
      url
    }
  }
}
]]

---@class octo.IssueType
---@field id string
---@field name string
---@field description string
---@field color string

M.issue_types = [[
query($owner: String!, $name: String!) {
  repository(owner: $owner, name: $name) {
    issueTypes(first: 100) {
      nodes {
        id
        name
        description
        color
      }
    }
  }
}
]]

return M
