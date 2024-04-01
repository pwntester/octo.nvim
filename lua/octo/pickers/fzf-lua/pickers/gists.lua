local fzf = require "fzf-lua"
local navigation = require "octo.navigation"
local picker_utils = require "octo.pickers.fzf-lua.pickers.utils"
local previewers = require "octo.pickers.fzf-lua.previewers"
local utils = require "octo.utils"

local open_gist = function(gist)
  for _, file in ipairs(gist.files) do
    local bufnr = vim.api.nvim_create_buf(true, true)
    if file.text then
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(file.text, "\n"))
    else
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, gist.description)
    end
    vim.api.nvim_buf_set_name(bufnr, file.name)
    vim.api.nvim_win_set_buf(0, bufnr)
    vim.api.nvim_buf_call(bufnr, function()
      vim.cmd [[filetype detect]]
    end)

    vim.api.nvim_buf_set_keymap(bufnr, "n", "<C-B>", "", {
      callback = function()
        navigation.open_in_browser("gist", nil, gist.name)
      end,
    })
  end
end

return function(opts)
  local privacy
  if opts.public then
    privacy = "PUBLIC"
  elseif opts.secret then
    privacy = "SECRET"
  else
    privacy = "ALL"
  end

  local formatted_gists = {}

  local get_contents = function(fzf_cb)
    local backend = require "octo.backend"
    local func = backend.get_funcs()["fzf_lua_gists"]
    func(formatted_gists, privacy, fzf_cb)
  end

  fzf.fzf_exec(get_contents, {
    prompt = picker_utils.get_prompt(opts.prompt_title),
    func_async_callback = false,
    previewer = previewers.gist(formatted_gists),
    fzf_opts = {
      ["--info"] = "default",
      ["--no-multi"] = "",
      ["--delimiter"] = "' '",
      ["--with-nth"] = "2..",
    },
    actions = {
      ["default"] = function(selected)
        open_gist(formatted_gists[selected[1]])
      end,
      ["ctrl-b"] = function(selected)
        picker_utils.open_in_browser(formatted_gists[selected[1]])
      end,
      ["ctrl-y"] = function(selected)
        local entry = formatted_gists[selected[1]]
        local url = string.format("https://gist.github.com/%s", entry.gist.name)
        vim.fn.setreg("+", url, "c")
        utils.info("Copied '" .. url .. "' to the system clipboard (+ register)")
      end,
    },
  })
end
