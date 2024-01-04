local M = {}

M.OCTO_COMMENT_NS = vim.api.nvim_create_namespace "octo_marks"
M.OCTO_HIGHLIGHT_NS = vim.api.nvim_create_namespace "octo_highlight"
M.OCTO_THREAD_NS = vim.api.nvim_create_namespace "octo_thread"
M.OCTO_REVIEW_COMMENTS_NS = vim.api.nvim_create_namespace "octo_review_comments"
M.OCTO_FILE_PANEL_NS = vim.api.nvim_create_namespace "octo_file_panel"

M.OCTO_TITLE_VT_NS = vim.api.nvim_create_namespace "octo_title_vt"
M.OCTO_REPO_VT_NS = vim.api.nvim_create_namespace "octo_title_vt"
M.OCTO_REACTIONS_VT_NS = vim.api.nvim_create_namespace "octo_reactions_vt"
M.OCTO_DETAILS_VT_NS = vim.api.nvim_create_namespace "octo_details_vt"
M.OCTO_DIFFHUNK_VT_NS = vim.api.nvim_create_namespace "octo_diffhunk_vt"
M.OCTO_PROFILE_VT_NS = vim.api.nvim_create_namespace "octo_profile_vt"
M.OCTO_SUMMARY_VT_NS = vim.api.nvim_create_namespace "octo_summary_vt"
M.OCTO_EMPTY_MSG_VT_NS = vim.api.nvim_create_namespace "octo_empty_msg_vt"
M.OCTO_THREAD_HEADER_VT_NS = vim.api.nvim_create_namespace "octo_thread_header_vt"
M.OCTO_EVENT_VT_NS = vim.api.nvim_create_namespace "octo_event_vt"

M.NO_BODY_MSG = "No description provided."

M.LONG_ISSUE_PATTERN = "([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)#(%d+)"
M.SHORT_ISSUE_PATTERN = "[^%w%d]+#(%d+)"
M.SHORT_ISSUE_LINE_BEGGINING_PATTERN = "^#(%d+)"
M.URL_ISSUE_PATTERN = "[htps]+://[^/]+/([^/]+/[^/]+)/([pulisue]+)/(%d+)"

M.USER_PATTERN = "@([%w-]+)"

return M
