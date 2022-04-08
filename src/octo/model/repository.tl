global type Repository = record
  hostname: string

  -- Is the full path of the repository/ project (owner+name).
  full_path: string
  -- The owner name.
  -- For GitLab repositories this would be the full group path
  -- and not only the root group.
  owner: string
  -- Is the name of the repository/ project.
  name: string
  id: integer
end

global type TimelineItemType = enum
  "LabeledEvent" -- Resolves to 'LabelEvent'
  "UnlabeledEvent" -- Resolves to 'LabelEvent'
  "IssueComment"
  "ClosedEvent"
  "ReopenedEvent"
  "AssignedEvent"
end

global type TimelineItem = record
  __typename: string

  itemType: TimelineItemType

  data: any
end

global type LabelEvent = record
  actor: User
  createdAt: string
  label: Label
end

global type IssueCommentEvent = record
  id: integer
  body: string
  createdAt: string
  reactionGroups: {ReactionGroup}
  actor: User
  viewerDidAuthor: boolean
  viewerCanUpdate: boolean
  viewerCanDelete: boolean
end

global type StateChangeEvent = record
  createdAt: string
  actor: string
end

global type AssignedEvent = record
  createdAt: string
  actor: User
  assignee: any -- TODO: Discuss how to handle
end

global type Issue = record
  __typename: string

  -- Is the repository the issue belongs to.
  repo: Repository

  -- Is the ID of the Issue within the repository/ project.
  -- For GitLab repos it's the IID.
  id: integer
  title: string
  author: User
  milestone: Milestone
  createdAt: string
  closedAt: string
  updatedAt: string
  description: string
  state: IssueState
  assignees: {User}
  participants: {User}
  labels: {Label}
  reactionGroups: {ReactionGroup}
  url: string -- Is the Web URL
  timelineItems: {TimelineItem}

  viewerDidAuthor: boolean
  viewerCanUpdate: boolean
end

global type ReactionGroup = record
end

global type IssueState = enum
  "all"
  "closed"
  "locked"
  "opened"
end

global type User = record
  id: integer
  username: string
  name: string

  -- Special Fields

  isViewer: boolean
end

global type Label = record
  name: string
  color: string
end

global type Milestone = record
  title: string

  enum MilestoneStateEnum
    "active"
    "close"
  end
  state: MilestoneStateEnum
end
