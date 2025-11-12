local M = {}

---@param msg string
---@param level? integer
function M.notify(msg, level)
  if level == 1 then
    level = vim.log.levels.INFO
  elseif level == 2 then
    level = vim.log.levels.ERROR
  elseif level == 3 then
    level = vim.log.levels.WARN
  else
    level = vim.log.levels.INFO
  end
  vim.notify(msg, level, { title = "Octo.nvim" })
end

---@param msg string
function M.info(msg)
  M.notify(msg, 1)
end

---@param msg string
function M.error(msg)
  M.notify(msg, 2)
end

---@param msg string
function M.warn(msg)
  M.notify(msg, 3)
end

return M
