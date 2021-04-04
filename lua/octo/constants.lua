local api = vim.api

local M = {}

M.OCTO_COMMENT_NS = api.nvim_create_namespace("octo_marks")

M.OCTO_HIGHLIGHT_NS = api.nvim_create_namespace("octo_highlight")

M.OCTO_THREAD_NS = api.nvim_create_namespace("octo_thread")

M.OCTO_TITLE_VT_NS = api.nvim_create_namespace("octo_title_vt")
M.OCTO_REACTIONS_VT_NS = api.nvim_create_namespace("octo_reactions_vt")
M.OCTO_DETAILS_VT_NS = api.nvim_create_namespace("octo_details_vt")
M.OCTO_DIFFHUNKS_VT_NS = api.nvim_create_namespace("octo_diffhunks_vt")
M.OCTO_EMPTY_MSG_VT_NS = api.nvim_create_namespace("octo_empty_msg_vt")
M.OCTO_THREAD_HEADER_VT_NS = api.nvim_create_namespace("octo_thread_header_vt")
M.OCTO_EVENT_VT_NS = api.nvim_create_namespace("octo_details_vt")

M.NO_BODY_MSG = "No description provided."

M.LONG_ISSUE_PATTERN = "([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)#(%d+)"
M.SHORT_ISSUE_PATTERN = "%s#(%d+)"
M.URL_ISSUE_PATTERN = ("[htps]+://[^/]+/([^/]+/[^/]+)/([pulisue]+)/(%d+)")

M.USER_PATTERN = "@(%S+)"

return M
