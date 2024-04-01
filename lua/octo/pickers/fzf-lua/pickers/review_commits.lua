local fzf = require "fzf-lua"
local previewers = require "octo.pickers.fzf-lua.previewers"
local utils = require "octo.utils"

-- add a fake entry to represent the entire pull request
local make_full_pr = function(current_review)
  return {
    sha = current_review.pull_request.right.commit,
    commit = {
      message = "[[ENTIRE PULL REQUEST]]",
      author = {
        name = "",
        email = "",
        date = "",
      },
    },
    parents = {
      {
        sha = current_review.pull_request.left.commit,
      },
    },
  }
end

return function(thread_cb)
  local current_review = require("octo.reviews").get_current_review()
  if not current_review then
    utils.error "No review in progress"
    return
  end

  local formatted_commits = {}

  local get_contents = function(fzf_cb)
    local backend = require "octo.backend"
    local func = backend.get_funcs()["fzf_lua_review_commits"]
    func(formatted_commits, current_review, make_full_pr, fzf_cb)
  end

  fzf.fzf_exec(get_contents, {
    previewer = previewers.commit(formatted_commits, current_review.pull_request.repo),
    fzf_opts = {
      ["--no-multi"] = "", -- TODO this can support multi, maybe.
      ["--info"] = "default",
      ["--delimiter"] = "' '",
      ["--with-nth"] = "2..",
    },
    actions = {
      ["default"] = function(selected)
        local entry = formatted_commits[selected[1]]
        thread_cb(entry.value, entry.parent)
      end,
    },
  })
end
