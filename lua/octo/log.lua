---@diagnostic disable: undefined-field
if _G.__is_log then
  return require("plenary.log").new {
    plugin = "octo.nvim",
    level = (_G.__is_log == true and "debug") or "warn",
  }
else
  return {
    debug = function(_) end,
    info = function(_) end,
    error = function(_) end,
  }
end
