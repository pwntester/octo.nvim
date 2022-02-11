local utils = require "octo.utils"

local M = {}

function M.not_implemented()
  utils.notify("Not implemented yet", 2)
end

M.picker = {
  issues = M.not_implemented,
  prs = M.not_implemented,
  gists = M.not_implemented,
  commits = M.not_implemented,
  changed_files = M.not_implemented,
  pending_threads = M.not_implemented,
  project_cards = M.not_implemented,
  project_columns = M.not_implemented,
  labels = M.not_implemented,
  assigned_labels = M.not_implemented,
  users = M.not_implemented,
  assignees = M.not_implemented,
  repos = M.not_implemented,
  search = M.not_implemented,
  actions = M.not_implemented,
}

return M
