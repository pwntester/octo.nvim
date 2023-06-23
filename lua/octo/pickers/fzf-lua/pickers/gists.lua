local entry_maker = require "octo.pickers.fzf-lua.entry_maker"
local fzf = require "fzf-lua"
local gh = require "octo.gh"
local graphql = require "octo.gh.graphql"
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
    local query = graphql("gists_query", privacy)

    gh.run {
      args = { "api", "graphql", "--paginate", "--jq", ".", "-f", string.format("query=%s", query) },
      stream_cb = function(output, stderr)
        if stderr and not utils.is_blank(stderr) then
          utils.error(stderr)
        elseif output then
          local resp = utils.aggregate_pages(output, "data.viewer.gists.nodes")
          local gists = resp.data.viewer.gists.nodes

          for _, gist in ipairs(gists) do
            local entry = entry_maker.gen_from_gist(gist)

            if entry ~= nil then
              formatted_gists[entry.ordinal] = entry
              fzf_cb(entry.ordinal)
            end
          end
        end

        fzf_cb()
      end,
      cb = function()
        fzf_cb()
      end,
    }
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
