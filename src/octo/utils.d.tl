require("octo.model.repository")

local record M
  get_split_and_path: function(bufnr: number): boolean, string
  split_repo: function(repo: string): string, string

  get_repository: function(): Repository
  get_issue_obj_uri: function(issue: Issue): string
  notify: function(msg: string, kind: any)
  is_blank: function(input: any): boolean
  aggregate_pages: function(data: string, aggregation_key: string): any
end

return M
