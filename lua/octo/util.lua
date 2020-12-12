local format = string.format

local M = {}

M.reaction_map = {
    ["+1"] = "👍",
    ["-1"] = "👎",
    ["laugh"] = "😀",
    ["hooray"] = "🎉",
    ["confused"] = "☹️",
    ["heart"] = "❤️",
    ["rocket"] = "🚀",
    ["eyes"] = "👀"
}

function M.is_blank(s)
	return not(s ~= nil and s:match("%S") ~= nil)
end

function M.get_remote_name(remote)
  remote = remote or 'origin'
	local cmd = format('git config --get remote.%s.url', remote)
  local url = string.gsub(vim.fn.system(cmd), '%s+', '')
	local owner, repo
  if #vim.split(url, '://') == 2 then
    owner = vim.split(url, '/')[#vim.split(url, '/')-1]
    repo = string.gsub(vim.split(url, '/')[#vim.split(url, '/')], '.git$', '')
  elseif #vim.split(url, '@') == 2 then
    local segment = vim.split(url, ':')[2]
    owner = vim.split(segment, '/')[1]
    repo = string.gsub(vim.split(segment, '/')[2], '.git$', '')
	end
	return format('%s/%s', owner, repo)
end

return M
