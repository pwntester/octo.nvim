--- Helpers for discussions
local gh = require "octo.gh"
local queries = require "octo.gh.queries"
local mutations = require "octo.gh.mutations"
local utils = require "octo.utils"

local M = {}

---@class DiscussionMutationOpts
---@field repo_id string
---@field category_id string
---@field title string
---@field body string

--- Discussion mutation
---@param opts DiscussionMutationOpts
local function create_discussion(opts)
  gh.api.graphql {
    query = mutations.create_discussion,
    fields = {
      repo_id = opts.repo_id,
      category_id = opts.category_id,
      title = opts.title,
      body = opts.body,
    },
    jq = ".data.createDiscussion.discussion",
    opts = {
      cb = gh.create_callback {
        success = function(output)
          utils.info("Successfully created discussion " .. opts.title)
          local resp = vim.json.decode(output)
          utils.copy_url(resp.url)
        end,
      },
    },
  }
end

---@class Category
---@field id string
---@field name string
---@field emoji string

---Select a category
---@param categories Category[]
---@param cb fun(selected: Category)
local function select_a_category(categories, cb)
  vim.ui.select(categories, {
    prompt = "Pick a category: ",
    format_item = function(item)
      return item.name
    end,
  }, function(selected)
    if selected == nil then
      return
    end
    cb(selected)
  end)
end

---@class GetCategoriesOpts
---@field owner string
---@field name string

---Get categories for a repository
---@param opts GetCategoriesOpts
---@param cb fun(selected: Category)
local function get_categories(opts, cb)
  gh.api.graphql {
    query = queries.discussion_categories,
    jq = ".data.repository.discussionCategories.nodes",
    fields = { owner = opts.owner, name = opts.name },
    opts = {
      cb = gh.create_callback {
        success = function(data)
          local categories = vim.json.decode(data)
          select_a_category(categories, cb)
        end,
      },
    },
  }
end

---@class DiscussionOpts
---@field repo string
---@field title string|nil
---@field body string|nil

---Create a discussion for a repository
---@param original_opts DiscussionOpts
---@return nil
function M.create(original_opts)
  ---@class octo.DiscussionOptsCombined : DiscussionOpts, GetCategoriesOpts, DiscussionMutationOpts
  local opts = original_opts or {}

  opts.owner, opts.name = utils.split_repo(opts.repo)
  local repo_info = utils.get_repo_info(opts.repo)
  if not repo_info then
    return
  end

  if not repo_info.hasDiscussionsEnabled then
    utils.error(opts.repo .. " doesn't have discussions enabled")
    return
  end

  opts.repo_id = repo_info.id

  if not opts.title then
    opts.title = utils.input { prompt = "Creating discussion for " .. opts.repo .. ". Enter title" }
  end
  if not opts.body then
    opts.body = utils.input { prompt = "Discussion body" }
  end

  local function cb(selected) ---@param selected Category
    opts.category_id = selected.id

    create_discussion(opts)
  end
  get_categories(opts, cb)
end

return M
