global type OctoBuffer = record
  bufnr: integer
  number: integer
  repo: string
  kind: string
  -- titleMetadata: TitleMetadata
  -- bodyMetadata: BodyMetadata
  -- commentsMetadata: CommentMetadata[]
  -- threadsMetadata: ThreadMetadata[]
  -- node: table
  -- taggable_users: string[]

  record newOpts
    bufnr: integer
    number: integer
    repo: any
    node: any
    kind: string
    -- commentsMetadata: CommentMetadata[]
    -- threadsMetadata: ThreadMetadata[]
  end

  new: function(self: OctoBuffer, newOpts): OctoBuffer
  apply_mappings: function(self: OctoBuffer)
  render_repo: function(self: OctoBuffer)
  render_issue: function(self: OctoBuffer)
  clear: function(self: OctoBuffer)

  -- NOTE: This is used (and defined) in writers.lua!!
  record Threads
    {Threads}

    path: string
    diffSide: string -- TODO: Type?
    originalStartLine: number
    originalLine: number
    isOutdated: boolean
    isResolved: boolean
    isCollapsed: boolean
    comments: any -- TODO: We know that this is an object.
  end
  render_threads: function(threads: Threads)

  configure: function(self: OctoBuffer)
  async_fetch_taggable_users: function(self: OctoBuffer)
  async_fetch_issues: function(self: OctoBuffer)
  save: function(self: OctoBuffer)
  render_signcolumn: function(self: OctoBuffer)
end

local record M
  OctoBuffer: OctoBuffer

  record Buffer
    titleMetadata: any
    bodyMetadata: any
    node: any -- NOTE: This is an object

    isIssue: function(): boolean
    isPullRequest: function(): boolean
    render_signcolumn: function()
  end
  do_save_title_and_body: function(buffer: Buffer)
end

return M
