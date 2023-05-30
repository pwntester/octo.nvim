local utils = require "octo.utils"

local M = {}

function M.not_implemented()
  utils.error "Not implemented yet"
end

M.picker = {
  issues = require "octo.pickers.fzf-lua.pickers.issues",
  prs = require "octo.pickers.fzf-lua.pickers.prs",
  gists = M.not_implemented,
  commits = require "octo.pickers.fzf-lua.pickers.commits",
  review_commits = M.not_implemented,
  changed_files = require "octo.pickers.fzf-lua.pickers.changed_files",
  pending_threads = M.not_implemented,
  project_cards = require "octo.pickers.fzf-lua.pickers.project_cards",
  project_columns = require "octo.pickers.fzf-lua.pickers.project_columns",
  labels = M.not_implemented,
  assigned_labels = M.not_implemented,
  users = M.not_implemented,
  assignees = M.not_implemented,
  repos = M.not_implemented,
  search = M.not_implemented,
  actions = M.not_implemented,
  issue_templates = M.not_implemented,
}

return M
