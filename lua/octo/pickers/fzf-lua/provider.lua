local utils = require "octo.utils"

local M = {}

function M.not_implemented()
  utils.error "Not implemented yet"
end

M.picker = {
  issues = require "octo.pickers.fzf-lua.pickers.issues",
  prs = require "octo.pickers.fzf-lua.pickers.prs",
  commits = require "octo.pickers.fzf-lua.pickers.commits",
  changed_files = require "octo.pickers.fzf-lua.pickers.changed_files",
  project_cards = require "octo.pickers.fzf-lua.pickers.project_cards",
  project_columns = require "octo.pickers.fzf-lua.pickers.project_columns",

  search = require "octo.pickers.fzf-lua.pickers.search",
  users = require "octo.pickers.fzf-lua.pickers.users",
  assignees = require "octo.pickers.fzf-lua.pickers.assignees",
  labels = require "octo.pickers.fzf-lua.pickers.labels",
  assigned_labels = require "octo.pickers.fzf-lua.pickers.assigned_labels",
  repos = require "octo.pickers.fzf-lua.pickers.repos",
  review_commits = require "octo.pickers.fzf-lua.pickers.review_commits",

  gists = require "octo.pickers.fzf-lua.pickers.gists",
  pending_threads = require "octo.pickers.fzf-lua.pickers.pending_threads",
  actions = require "octo.pickers.fzf-lua.pickers.actions",
  issue_templates = require "octo.pickers.fzf-lua.pickers.issue_templates",
}

return M
