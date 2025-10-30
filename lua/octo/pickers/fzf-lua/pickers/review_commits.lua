---@diagnostic disable
local entry_maker = require "octo.pickers.fzf-lua.entry_maker"
local fzf = require "fzf-lua"
local gh = require "octo.gh"
local previewers = require "octo.pickers.fzf-lua.previewers"
local utils = require "octo.utils"

-- add a fake entry to represent the entire pull request
---@param current_review Review
local function make_full_pr(current_review)
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

---@param current_review Review
---@param callback fun(left: Rev, right: Rev): nil
return function(current_review, callback)
  local formatted_commits = {}

  local function get_contents(fzf_cb)
    gh.api.get {
      "/repos/{repo}/pulls/{number}/commits",
      format = { repo = current_review.pull_request.repo, number = current_review.pull_request.number },
      opts = {
        cb = function(output, err)
          if err and not utils.is_blank(err) then
            utils.error(err)
            fzf_cb()
          elseif output then
            local results = vim.json.decode(output)

            if #formatted_commits == 0 then
              local full_pr = entry_maker.gen_from_git_commits(make_full_pr(current_review))
              formatted_commits["000 [[ENTIRE PULL REQUEST]]"] = full_pr
              fzf_cb "000 [[ENTIRE PULL REQUEST]]"
            end

            for _, commit in ipairs(results) do
              local entry = entry_maker.gen_from_git_commits(commit)

              if entry ~= nil then
                formatted_commits[entry.ordinal] = entry
                fzf_cb(entry.ordinal)
              end
            end
          end

          fzf_cb()
        end,
      },
    }
  end

  fzf.fzf_exec(get_contents, {
    previewer = previewers.commit(formatted_commits, current_review.pull_request.repo),
    fzf_opts = {
      ["--no-multi"] = "", -- TODO this can support multi, maybe.
      ["--info"] = "default",
      ["--delimiter"] = " ",
      ["--with-nth"] = "2..",
    },
    actions = {
      ["default"] = function(selected)
        local entry = formatted_commits[selected[1]]
        callback(entry.value, entry.parent)
      end,
    },
  })
end
