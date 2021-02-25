local api = vim.api

local M = {}

M.OCTO_EM_NS = api.nvim_create_namespace("octo_marks")
M.OCTO_TITLE_VT_NS = api.nvim_create_namespace("octo_title_vt")
M.OCTO_REACTIONS_VT_NS = api.nvim_create_namespace("octo_reactions_vt")
M.OCTO_DETAILS_VT_NS = api.nvim_create_namespace("octo_details_vt")
M.OCTO_DIFFHUNKS_VT_NS = api.nvim_create_namespace("octo_diffhunks_vt")
M.OCTO_EMPTY_MSG_VT_NS = api.nvim_create_namespace("octo_empty_msg_vt")
M.OCTO_HIGHLIGHT_NS = api.nvim_create_namespace("octo_highlight")
M.OCTO_THREAD_HEADER_VT_NS = api.nvim_create_namespace("octo_thread_header_vt")
M.NO_BODY_MSG = "No description provided."

return M
