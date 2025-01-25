local utils = require "octo.utils"

local M = {}

function M.not_implemented()
  utils.error "Not implemented yet"
end

M.picker = {
  actions = require "octo.pickers.fzf-lua.pickers.actions",
  assigned_labels = require "octo.pickers.fzf-lua.pickers.assigned_labels",
  assignees = require "octo.pickers.fzf-lua.pickers.assignees",
  changed_files = require "octo.pickers.fzf-lua.pickers.changed_files",
  discussions = M.not_implemented,
  commits = require "octo.pickers.fzf-lua.pickers.commits",
  gists = require "octo.pickers.fzf-lua.pickers.gists",
  issue_templates = require "octo.pickers.fzf-lua.pickers.issue_templates",
  issues = require "octo.pickers.fzf-lua.pickers.issues",
  labels = require "octo.pickers.fzf-lua.pickers.labels",
  pending_threads = require "octo.pickers.fzf-lua.pickers.pending_threads",
  project_cards = require "octo.pickers.fzf-lua.pickers.project_cards",
  project_cards_v2 = require "octo.pickers.fzf-lua.pickers.project_cards_v2",
  project_columns = require "octo.pickers.fzf-lua.pickers.project_columns",
  project_columns_v2 = require "octo.pickers.fzf-lua.pickers.project_columns_v2",
  prs = require "octo.pickers.fzf-lua.pickers.prs",
  repos = require "octo.pickers.fzf-lua.pickers.repos",
  review_commits = require "octo.pickers.fzf-lua.pickers.review_commits",
  search = require "octo.pickers.fzf-lua.pickers.search",
  users = require "octo.pickers.fzf-lua.pickers.users",
  notifications = M.not_implemented,
  milestones = M.not_implemented,
}

return M
