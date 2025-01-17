local utils = require "octo.utils"

local M = {}

function M.not_implemented()
  utils.error "Not implemented yet"
end

M.picker = {
  actions = M.not_implemented,
  assigned_labels = M.not_implemented,
  assignees = M.not_implemented,
  changed_files = M.not_implemented,
  commits = M.not_implemented,
  discussions = M.not_implemented,
  gists = M.not_implemented,
  issue_templates = M.not_implemented,
  issues = M.not_implemented,
  labels = M.not_implemented,
  notifications = M.not_implemented,
  pending_threads = M.not_implemented,
  project_cards = M.not_implemented,
  project_cards_v2 = M.not_implemented,
  project_columns = M.not_implemented,
  project_columns_v2 = M.not_implemented,
  prs = M.not_implemented,
  repos = M.not_implemented,
  review_commits = M.not_implemented,
  search = M.not_implemented,
  users = M.not_implemented,
  milestones = M.not_implemented,
}

return M
