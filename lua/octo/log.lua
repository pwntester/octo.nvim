local has_plenary_log, _ = pcall(require, "plenary.log")
if not has_plenary_log then
  return {
    trace = print,
    warn = print,
    debug = print,
    info = print,
    error = print,
    fatal = print,
  }
else
  return require("plenary.log").new {
    plugin = "octo",
    level = (vim.loop.os_getenv "USER" == "pwntester" and "debug") or "warn",
  }
end
