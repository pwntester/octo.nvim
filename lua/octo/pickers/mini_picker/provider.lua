local gh = require "octo.gh"
local graphql = require "octo.gh.graphql"
local utils = require "octo.utils"
local octo_config = require "octo.config"
local queries = require "octo.gh.queries"
local reviews = require "octo.reviews"

-- get_filter function
local function get_filter(filter_opts, kind)
  local filter = ""
  local allowed_values = {}
  if kind == "issue" then
    allowed_values = { "since", "createdBy", "assignee", "mentioned", "labels", "milestone", "states" }
  elseif kind == "pull_request" then
    allowed_values =
      { "baseRefName", "headRefName", "labels", "states", "author", "mentions", "review-requested", "review-concluded" }
  end

  for _, value in pairs(allowed_values) do
    if filter_opts[value] then
      local val
      if type(filter_opts[value]) == "table" then
        val = filter_opts[value]
      elseif type(filter_opts[value]) == "string" and #vim.split(filter_opts[value], ",") > 1 then
        val = vim.split(filter_opts[value], ",")
      else
        val = filter_opts[value]
      end

      local encoded_val = vim.json.encode(val)
      encoded_val = string.gsub(encoded_val, '"OPEN"', "OPEN")
      encoded_val = string.gsub(encoded_val, '"CLOSED"', "CLOSED")
      encoded_val = string.gsub(encoded_val, '"MERGED"', "MERGED")

      filter = filter .. value .. ":" .. encoded_val .. ","
    end
  end
  if string.sub(filter, -1) == "," then
    filter = string.sub(filter, 1, -2)
  end
  return filter
end

local M = {}

M.picker = {
  -- issues function
  issues = function(opts)
    opts = opts or {}
    if not opts.states then
      opts.states = "OPEN"
    end

    local filter_str = get_filter(opts, "issue")
    if utils.is_blank(opts.repo) then
      opts.repo = utils.get_remote_name()
    end
    if not opts.repo then
      utils.error "Cannot find repo"
      return
    end

    local owner, name = utils.split_repo(opts.repo)
    local cfg = octo_config.values
    local order_by = cfg.issues.order_by
    local query =
      graphql("issues_query", owner, name, filter_str, order_by.field, order_by.direction, { escape = false })

    utils.info "Fetching issues (this may take a while) ..."
    gh.run {
      args = { "api", "graphql", "--paginate", "--jq", ".", "-f", string.format("query=%s", query) },
      cb = function(output, stderr)
        if stderr and not utils.is_blank(stderr) then
          utils.error(stderr)
        elseif output then
          local resp = utils.aggregate_pages(output, "data.repository.issues.nodes")
          local issues_data = resp.data.repository.issues.nodes
          if #issues_data == 0 then
            utils.error(string.format("There are no matching issues in %s.", opts.repo))
            return
          end

          local items_for_picker = {}
          for _, issue_item in ipairs(issues_data) do
            table.insert(items_for_picker, {
              text = string.format("#%d %s", issue_item.number, issue_item.title),
              data = issue_item,
              repo = opts.repo,
            })
          end

          local function choose_issue(item)
            if item and item.data then
              utils.get("issue", item.data.number, item.repo)
            end
            return false
          end

          local MiniPick = _G.MiniPick
          if not MiniPick then
            utils.error "MiniPick is not loaded. Please ensure 'mini.pick' is installed and setup."
            return
          end

          MiniPick.start {
            source = {
              items = items_for_picker,
              name = "Issues (" .. opts.repo .. ")",
              choose = choose_issue,
            },
            options = {
              content_from_bottom = cfg.picker_config
                  and cfg.picker_config.mini_picker
                  and cfg.picker_config.mini_picker.content_from_bottom
                or false,
            },
          }
        end
      end,
    }
  end,

  -- prs function
  prs = function(opts)
    opts = opts or {}
    if not opts.states then
      opts.states = "OPEN"
    end

    local filter_str = get_filter(opts, "pull_request")
    if utils.is_blank(opts.repo) then
      opts.repo = utils.get_remote_name()
    end
    if not opts.repo then
      utils.error "Cannot find repo"
      return
    end

    local owner, name = utils.split_repo(opts.repo)
    local cfg = octo_config.values
    local order_by = cfg.pull_requests and cfg.pull_requests.order_by or cfg.issues.order_by
    local query =
      graphql("pull_requests_query", owner, name, filter_str, order_by.field, order_by.direction, { escape = false })

    utils.info "Fetching pull requests (this may take a while) ..."
    gh.run {
      args = { "api", "graphql", "--paginate", "--jq", ".", "-f", string.format("query=%s", query) },
      cb = function(output, stderr)
        if stderr and not utils.is_blank(stderr) then
          utils.error(stderr)
        elseif output then
          local resp = utils.aggregate_pages(output, "data.repository.pullRequests.nodes")
          local pr_data_list = resp.data.repository.pullRequests.nodes
          if #pr_data_list == 0 then
            utils.error(string.format("There are no matching pull requests in %s.", opts.repo))
            return
          end

          local items_for_picker = {}
          for _, pr_item in ipairs(pr_data_list) do
            table.insert(items_for_picker, {
              text = string.format("#%d %s", pr_item.number, pr_item.title),
              data = pr_item,
              repo = opts.repo,
            })
          end

          local function choose_pr(item)
            if item and item.data then
              utils.get("pr", item.data.number, item.repo)
            end
            return false
          end

          local MiniPick = _G.MiniPick
          if not MiniPick then
            utils.error "MiniPick is not loaded. Please ensure 'mini.pick' is installed and setup."
            return
          end

          MiniPick.start {
            source = {
              items = items_for_picker,
              name = "Pull Requests (" .. opts.repo .. ")",
              choose = choose_pr,
            },
            options = {
              content_from_bottom = cfg.picker_config
                  and cfg.picker_config.mini_picker
                  and cfg.picker_config.mini_picker.content_from_bottom
                or false,
            },
          }
        end
      end,
    }
  end,

  -- changed_files function
  changed_files = function(opts)
    opts = opts or {}
    local buffer = utils.get_current_buffer()
    if not buffer or not buffer:isPullRequest() then
      utils.error "Not in a Pull Request buffer. Cannot determine changed files."
      return
    end

    local repo_owner = buffer.owner
    local repo_name = buffer.name
    local pr_number = buffer.number

    if not repo_owner or not repo_name or not pr_number then
      utils.error "Could not determine repository or PR number from current buffer."
      return
    end

    local url = string.format("repos/%s/%s/pulls/%d/files", repo_owner, repo_name, pr_number)
    utils.info("Fetching changed files for PR #" .. pr_number .. "...")

    gh.run {
      args = { "api", "--paginate", url },
      cb = function(output, stderr)
        if stderr and not utils.is_blank(stderr) then
          utils.error("Error fetching changed files: " .. stderr)
        elseif output then
          local files_data = vim.json.decode(output)
          if not files_data or #files_data == 0 then
            utils.error(string.format("No changed files found for PR #%d in %s/%s.", pr_number, repo_owner, repo_name))
            return
          end

          local items_for_picker = {}
          for _, file_item in ipairs(files_data) do
            local status_char = ""
            if file_item.status == "added" then
              status_char = "A"
            elseif file_item.status == "modified" then
              status_char = "M"
            elseif file_item.status == "removed" then
              status_char = "D"
            elseif file_item.status == "renamed" then
              status_char = "R"
            end
            table.insert(items_for_picker, {
              text = string.format(
                "[%s] %s (+%d/-%d)",
                status_char,
                file_item.filename,
                file_item.additions,
                file_item.deletions
              ),
              data = file_item,
              repo_full_name = repo_owner .. "/" .. repo_name,
              pr_number = pr_number,
            })
          end

          local function choose_file(item)
            if item and item.data then
              utils.info(string.format("Selected file: %s (Status: %s)", item.data.filename, item.data.status))
              vim.notify(string.format("Octo: Would open diff for %s", item.data.filename), vim.log.levels.INFO)
            end
            return false
          end

          local MiniPick = _G.MiniPick
          if not MiniPick then
            utils.error "MiniPick is not loaded. Please ensure 'mini.pick' is installed and setup."
            return
          end

          local cfg = octo_config.values
          MiniPick.start {
            source = {
              items = items_for_picker,
              name = string.format("Changed Files (PR #%d)", pr_number),
              choose = choose_file,
            },
            options = {
              content_from_bottom = cfg.picker_config
                  and cfg.picker_config.mini_picker
                  and cfg.picker_config.mini_picker.content_from_bottom
                or false,
            },
          }
        end
      end,
    }
  end,

  -- search function
  search = function(opts)
    opts = opts or {}
    opts.type = opts.type or "ISSUE"

    if utils.is_blank(opts.prompt) then
      utils.error "Search prompt cannot be empty."
      return
    end

    utils.info(string.format("Searching for %s: %s", opts.type, opts.prompt))

    gh.api.graphql {
      query = queries.search,
      fields = { prompt = opts.prompt, type = opts.type },
      jq = ".data.search.nodes",
      opts = { mode = "sync" },
      cb = gh.create_callback {
        success = function(output)
          local results = vim.json.decode(output or "[]")
          if #results == 0 then
            utils.error(string.format("No %s found for '%s'", opts.type, opts.prompt))
            return
          end

          local items_for_picker = {}
          for _, item_data in ipairs(results) do
            local text_display = ""
            if opts.type == "ISSUE" or opts.type == "PULL_REQUEST" then
              text_display = string.format(
                "#%s %s (%s)",
                item_data.number or "N/A",
                item_data.title or "No Title",
                item_data.repository and item_data.repository.nameWithOwner or "Unknown Repo"
              )
            elseif opts.type == "REPOSITORY" then
              text_display = string.format(
                "%s (⭐%d, 🍴%d)",
                item_data.nameWithOwner or "Unknown Repo",
                item_data.stargazerCount or 0,
                item_data.forkCount or 0
              )
            else
              text_display = item_data.title or item_data.name or item_data.login or "Unknown item"
            end
            table.insert(items_for_picker, {
              text = text_display,
              data = item_data,
              type = opts.type,
            })
          end

          local function choose_search_item(selected_item)
            if selected_item and selected_item.data then
              local item_data = selected_item.data
              local item_type = selected_item.type
              if item_type == "ISSUE" then
                utils.get("issue", item_data.number, item_data.repository.nameWithOwner)
              elseif item_type == "PULL_REQUEST" then
                utils.get("pr", item_data.number, item_data.repository.nameWithOwner)
              elseif item_type == "REPOSITORY" then
                utils.open_in_browser("repo", item_data.nameWithOwner)
              else
                utils.info("Selected: " .. (item_data.title or item_data.nameWithOwner or "Unknown"))
              end
            end
            return false
          end

          local MiniPick = _G.MiniPick
          if not MiniPick then
            utils.error "MiniPick is not loaded."
            return
          end
          local cfg = octo_config.values
          MiniPick.start {
            source = {
              items = items_for_picker,
              name = string.format("Search Results (%s)", opts.type),
              choose = choose_search_item,
            },
            options = {
              content_from_bottom = cfg.picker_config
                  and cfg.picker_config.mini_picker
                  and cfg.picker_config.mini_picker.content_from_bottom
                or false,
            },
          }
        end,
        error = function(err_output)
          utils.error("Error during search: " .. err_output)
        end,
      },
    }
  end,

  -- repos function
  repos = function(opts)
    opts = opts or {}
    local login = opts.login

    utils.info(string.format("Fetching repositories%s", login and (" for " .. login) or ""))

    gh.api.graphql {
      query = queries.repos,
      fields = { login = login },
      paginate = true,
      jq = ".data.repositoryOwner.repositories.nodes",
      opts = {
        cb = gh.create_callback {
          success = function(output)
            local repos_data = utils.get_flatten_pages(output)
            if #repos_data == 0 then
              utils.error(string.format("No repositories found%s.", login and (" for " .. login) or ""))
              return
            end

            local items_for_picker = {}
            for _, repo_item in ipairs(repos_data) do
              table.insert(items_for_picker, {
                text = string.format(
                  "%s (⭐%d, 🍴%d)",
                  repo_item.nameWithOwner,
                  repo_item.forkCount or 0,
                  repo_item.stargazerCount or 0
                ),
                data = repo_item,
              })
            end

            local function choose_repo(selected_item)
              if selected_item and selected_item.data then
                utils.open_in_browser("repo", selected_item.data.nameWithOwner)
              end
              return false
            end

            local MiniPick = _G.MiniPick
            if not MiniPick then
              utils.error "MiniPick is not loaded."
              return
            end
            local cfg = octo_config.values
            MiniPick.start {
              source = {
                items = items_for_picker,
                name = string.format("Repositories%s", login and (" (" .. login .. ")") or ""),
                choose = choose_repo,
              },
              options = {
                content_from_bottom = cfg.picker_config
                    and cfg.picker_config.mini_picker
                    and cfg.picker_config.mini_picker.content_from_bottom
                  or false,
              },
            }
          end,
          error = function(err_output)
            utils.error("Error fetching repositories: " .. err_output)
          end,
        },
      },
    }
  end,

  -- labels function
  labels = function(opts)
    opts = opts or {}
    local repo = opts.repo or utils.get_remote_name()
    if not repo then
      utils.error "Cannot determine repository for labels."
      return
    end
    local owner, name = utils.split_repo(repo)

    utils.info("Fetching labels for " .. repo .. "...")
    gh.api.graphql {
      query = queries.labels_query,
      fields = { owner = owner, name = name },
      jq = ".data.repository.labels.nodes",
      opts = {
        cb = gh.create_callback {
          success = function(output)
            local labels_data = vim.json.decode(output or "[]")
            if #labels_data == 0 then
              utils.error(string.format("No labels found for %s.", repo))
              return
            end

            local items_for_picker = {}
            for _, label_item in ipairs(labels_data) do
              table.insert(items_for_picker, {
                text = label_item.name,
                data = label_item,
              })
            end

            local function choose_label(selected_item)
              if selected_item and selected_item.data then
                if opts.cb then
                  opts.cb(selected_item.data)
                else
                  utils.info("Selected label: " .. selected_item.data.name)
                end
              end
              return false
            end

            local MiniPick = _G.MiniPick
            if not MiniPick then
              utils.error "MiniPick is not loaded."
              return
            end
            local cfg = octo_config.values
            MiniPick.start {
              source = {
                items = items_for_picker,
                name = "Labels (" .. repo .. ")",
                choose = choose_label,
              },
              options = {
                content_from_bottom = cfg.picker_config
                    and cfg.picker_config.mini_picker
                    and cfg.picker_config.mini_picker.content_from_bottom
                  or false,
              },
            }
          end,
          error = function(err_output)
            utils.error("Error fetching labels: " .. err_output)
          end,
        },
      },
    }
  end,

  -- milestones function
  milestones = function(opts)
    opts = opts or {}
    if not opts.cb then
      utils.error "Callback action (opts.cb) for milestone selection is required."
      return
    end
    local repo = opts.repo or utils.get_remote_name()
    if not repo then
      utils.error "Cannot determine repository for milestones."
      return
    end
    local owner, name = utils.split_repo(repo)

    utils.info("Fetching open milestones for " .. repo .. "...")
    gh.api.graphql {
      query = queries.open_milestones,
      fields = { owner = owner, name = name, n_milestones = 100 },
      jq = ".data.repository.milestones.nodes",
      opts = {
        cb = gh.create_callback {
          success = function(output)
            local milestones_data = vim.json.decode(output or "[]")
            if #milestones_data == 0 then
              utils.error(string.format("No open milestones found in %s.", repo))
              return
            end

            local items_for_picker = {}
            for _, milestone_item in ipairs(milestones_data) do
              table.insert(items_for_picker, {
                text = milestone_item.title,
                data = milestone_item,
              })
            end

            local function choose_milestone(selected_item)
              if selected_item and selected_item.data then
                opts.cb(selected_item.data)
              end
              return false
            end

            local MiniPick = _G.MiniPick
            if not MiniPick then
              utils.error "MiniPick is not loaded."
              return
            end
            local cfg = octo_config.values
            MiniPick.start {
              source = {
                items = items_for_picker,
                name = "Milestones (" .. repo .. ")",
                choose = choose_milestone,
              },
              options = {
                content_from_bottom = cfg.picker_config
                    and cfg.picker_config.mini_picker
                    and cfg.picker_config.mini_picker.content_from_bottom
                  or false,
              },
            }
          end,
          error = function(err_output)
            utils.error("Error fetching milestones: " .. err_output)
          end,
        },
      },
    }
  end,

  users = function(opts) -- Corresponds to select_user
    opts = opts or {}
    local cfg = octo_config.values
    local selection_type = cfg.users -- "search", "mentionable", "assignable"
    local repo_for_context = opts.repo or utils.get_remote_name()

    local items_producer
    local picker_name = "Users"

    if selection_type == "search" then
      picker_name = "Search Users"
      items_producer = function(callback)
        local search_prompt = opts.prompt
        if not search_prompt or utils.is_blank(search_prompt) then
          utils.warn "User search type is 'search' but no prompt was provided. Showing no users."
          callback {} -- Return empty list if no prompt for search
          return
        end
        utils.info("Searching users with prompt: " .. search_prompt)
        gh.api.graphql {
          query = queries.users_query, -- expects a 'prompt' variable
          fields = { prompt = search_prompt },
          jq = ".data.search.nodes", -- Assuming this jq path
          opts = {
            cb = gh.create_callback {
              success = function(output)
                callback(vim.json.decode(output or "[]"))
              end,
              error = function(err)
                utils.error("User search failed: " .. err)
                callback {}
              end,
            },
          },
        }
      end
    elseif selection_type == "mentionable" then
      picker_name = "Mentionable Users"
      items_producer = function(callback)
        if not repo_for_context then
          utils.error "Cannot determine repository for mentionable users."
          callback {}
          return
        end
        local owner, name = utils.split_repo(repo_for_context)
        utils.info("Fetching mentionable users for " .. repo_for_context)
        gh.api.graphql {
          query = queries.mentionable_users,
          fields = { owner = owner, name = name },
          paginate = true,
          jq = ".data.repository.mentionableUsers.nodes",
          opts = {
            cb = gh.create_callback {
              success = function(output)
                callback(utils.get_flatten_pages(output))
              end,
              error = function(err)
                utils.error("Failed to fetch mentionable users: " .. err)
                callback {}
              end,
            },
          },
        }
      end
    elseif selection_type == "assignable" then
      picker_name = "Assignable Users"
      items_producer = function(callback)
        if not repo_for_context then
          utils.error "Cannot determine repository for assignable users."
          callback {}
          return
        end
        local owner, name = utils.split_repo(repo_for_context)
        utils.info("Fetching assignable users for " .. repo_for_context)
        gh.api.graphql {
          query = queries.assignable_users,
          fields = { owner = owner, name = name },
          paginate = true,
          jq = ".data.repository.assignableUsers.nodes",
          opts = {
            cb = gh.create_callback {
              success = function(output)
                callback(utils.get_flatten_pages(output))
              end,
              error = function(err)
                utils.error("Failed to fetch assignable users: " .. err)
                callback {}
              end,
            },
          },
        }
      end
    else
      utils.error("Invalid user selection type in config: " .. selection_type)
      return
    end

    items_producer(function(users_data)
      if #users_data == 0 then
        utils.info(
          string.format(
            "No users found for type '%s'%s.",
            selection_type,
            repo_for_context and (" in " .. repo_for_context)
              or (opts.prompt and (" with prompt '" .. opts.prompt .. "'") or "")
          )
        )
        return
      end

      local items_for_picker = {}
      for _, user_item in ipairs(users_data) do
        table.insert(items_for_picker, {
          text = user_item.login .. (user_item.name and (" (" .. user_item.name .. ")") or ""),
          data = user_item,
        })
      end

      local function choose_user(selected_item)
        if selected_item and selected_item.data then
          if opts.cb then
            opts.cb(selected_item.data)
          else
            utils.info("Selected user: " .. selected_item.data.login)
          end
        end
        return false
      end

      local MiniPick = _G.MiniPick
      if not MiniPick then
        utils.error "MiniPick is not loaded."
        return
      end
      MiniPick.start {
        source = {
          items = items_for_picker,
          name = picker_name .. (repo_for_context and (" (" .. repo_for_context .. ")") or ""),
          choose = choose_user,
        },
        options = {
          content_from_bottom = cfg.picker_config
              and cfg.picker_config.mini_picker
              and cfg.picker_config.mini_picker.content_from_bottom
            or false,
        },
      }
    end)
  end,

  assignees = function(opts)
    opts = opts or {}
    local buffer = utils.get_current_buffer()
    if not buffer or not (buffer:isIssue() or buffer:isPullRequest()) then
      utils.error "Not in an Issue or Pull Request buffer."
      return
    end

    local query_name
    local jq_path
    if buffer:isIssue() then
      query_name = "issue_assignees_query"
      jq_path = ".data.repository.issue.assignees.nodes"
    else
      query_name = "pull_request_assignees_query"
      jq_path = ".data.repository.pullRequest.assignees.nodes"
    end

    utils.info("Fetching assignees for current " .. (buffer:isIssue() and "issue" or "PR") .. "...")
    gh.api.graphql {
      query = graphql(query_name, buffer.owner, buffer.name, buffer.number),
      jq = jq_path,
      opts = {
        cb = gh.create_callback {
          success = function(output)
            local assignees_data = vim.json.decode(output or "[]")
            if #assignees_data == 0 then
              utils.info "No assignees found for the current item."
              return
            end

            local items_for_picker = {}
            for _, assignee_item in ipairs(assignees_data) do
              table.insert(items_for_picker, {
                text = assignee_item.login .. (assignee_item.name and (" (" .. assignee_item.name .. ")") or ""),
                data = assignee_item,
              })
            end

            local function choose_assignee(selected_item)
              if selected_item and selected_item.data then
                if opts.cb then
                  opts.cb(selected_item.data)
                else
                  utils.info("Selected assignee: " .. selected_item.data.login)
                end
              end
              return false
            end

            local MiniPick = _G.MiniPick
            if not MiniPick then
              utils.error "MiniPick is not loaded."
              return
            end
            local cfg = octo_config.values
            MiniPick.start {
              source = {
                items = items_for_picker,
                name = "Assignees",
                choose = choose_assignee,
              },
              options = {
                content_from_bottom = cfg.picker_config
                    and cfg.picker_config.mini_picker
                    and cfg.picker_config.mini_picker.content_from_bottom
                  or false,
              },
            }
          end,
          error = function(err)
            utils.error("Failed to fetch assignees: " .. err)
          end,
        },
      },
    }
  end,

  gists = function(opts)
    opts = opts or {}
    local privacy = "ALL"
    if opts.public then
      privacy = "PUBLIC"
    elseif opts.secret then
      privacy = "SECRET"
    end

    utils.info("Fetching gists (" .. privacy .. ")...")
    gh.run {
      args = {
        "api",
        "graphql",
        "--paginate",
        "--jq",
        ".",
        "-f",
        string.format("query=%s", graphql("gists_query", privacy)),
      },
      cb = function(output, stderr)
        if stderr and not utils.is_blank(stderr) then
          utils.error("Error fetching gists: " .. stderr)
        elseif output then
          local resp = utils.aggregate_pages(output, "data.viewer.gists.nodes")
          local gists_data = resp.data.viewer.gists.nodes
          if #gists_data == 0 then
            utils.info("No gists found with privacy: " .. privacy)
            return
          end

          local items_for_picker = {}
          for _, gist_item in ipairs(gists_data) do
            local description = gist_item.description
              or (gist_item.files and #gist_item.files > 0 and gist_item.files[1].name or "No description")
            table.insert(items_for_picker, {
              text = description,
              data = gist_item,
            })
          end

          local function choose_gist(selected_item)
            if selected_item and selected_item.data and selected_item.data.url then
              utils.open_in_browser_from_url(selected_item.data.url) -- Assuming gist URL is directly usable
            elseif selected_item and selected_item.data then
              utils.warn("Selected gist does not have a direct URL: " .. (selected_item.data.id or selected_item.text))
            end
            return false
          end

          local MiniPick = _G.MiniPick
          if not MiniPick then
            utils.error "MiniPick is not loaded."
            return
          end
          local cfg = octo_config.values
          MiniPick.start {
            source = {
              items = items_for_picker,
              name = "Gists (" .. privacy .. ")",
              choose = choose_gist,
              -- preview = function(buf_id, item_to_preview) ... end -- could show files in gist
            },
            options = {
              content_from_bottom = cfg.picker_config
                  and cfg.picker_config.mini_picker
                  and cfg.picker_config.mini_picker.content_from_bottom
                or false,
            },
          }
        end
      end,
    }
  end,

  notifications = function(opts)
    opts = opts or {}
    opts.all = opts.all or false -- Default to unread notifications
    local cfg = octo_config.values -- For mappings later, if any

    local endpoint = "/notifications"
    local picker_title = "Github Notifications"
    if opts.repo then
      local owner, name = utils.split_repo(opts.repo)
      endpoint = string.format("/repos/%s/%s/notifications", owner, name)
      picker_title = string.format("%s Notifications", opts.repo)
    end

    utils.info(
      "Fetching notifications"
        .. (opts.repo and (" for " .. opts.repo) or "")
        .. (opts.all and " (all)" or " (unread)")
        .. "..."
    )

    gh.api.get {
      endpoint,
      paginate = true,
      F = { all = opts.all },
      opts = {
        headers = { "Accept: application/vnd.github.v3+json" }, -- Ensure correct API version
        cb = gh.create_callback {
          success = function(output)
            local notifications_data = vim.json.decode(output or "[]")
            if #notifications_data == 0 then
              utils.info "There are no notifications."
              return
            end

            local items_for_picker = {}
            for _, notif_item in ipairs(notifications_data) do
              table.insert(items_for_picker, {
                text = string.format(
                  "[%s] %s",
                  notif_item.repository and notif_item.repository.name or "Global",
                  notif_item.subject.title
                ),
                data = notif_item,
              })
            end

            local function choose_notification(selected_item)
              if
                selected_item
                and selected_item.data
                and selected_item.data.subject
                and selected_item.data.subject.url
              then
                utils.info("Fetching HTML URL for notification: " .. selected_item.data.subject.title)
                gh.api.get {
                  selected_item.data.subject.url,
                  opts = {
                    headers = { "Accept: application/vnd.github.v3+json" },
                    cb = gh.create_callback {
                      success = function(subject_details_output)
                        local subject_details = vim.json.decode(subject_details_output)
                        if subject_details and subject_details.html_url then
                          utils.open_in_browser_from_url(subject_details.html_url)
                        else
                          utils.error "Could not determine HTML URL for the notification."
                        end
                      end,
                      error = function(err)
                        utils.error("Failed to fetch notification details: " .. err)
                      end,
                    },
                  },
                }
              else
                utils.warn "Selected notification does not have a subject URL."
              end
              return false
            end

            local MiniPick = _G.MiniPick
            if not MiniPick then
              utils.error "MiniPick is not loaded."
              return
            end
            MiniPick.start {
              source = {
                items = items_for_picker,
                name = picker_title,
                choose = choose_notification,
              },
              options = {
                content_from_bottom = cfg.picker_config
                    and cfg.picker_config.mini_picker
                    and cfg.picker_config.mini_picker.content_from_bottom
                  or false,
              },
            }
          end,
          error = function(err)
            utils.error("Error fetching notifications: " .. err)
          end,
        },
      },
    }
  end,

  issue_templates = function(opts)
    opts = opts or {}
    local templates = opts.templates
    local cb = opts.cb

    if not templates or #templates == 0 then
      utils.info "No issue templates provided."
      return
    end
    if not cb then
      utils.error "Callback (opts.cb) for issue template selection is required."
      return
    end

    local items_for_picker = {}
    for _, template_item in ipairs(templates) do
      table.insert(items_for_picker, {
        text = template_item.name,
        data = template_item,
      })
    end

    local function choose_template(selected_item)
      if selected_item and selected_item.data then
        cb(selected_item.data)
      end
      return false
    end

    local MiniPick = _G.MiniPick
    if not MiniPick then
      utils.error "MiniPick is not loaded."
      return
    end
    local cfg = octo_config.values
    MiniPick.start {
      source = {
        items = items_for_picker,
        name = "Issue Templates",
        choose = choose_template,
      },
      options = {
        content_from_bottom = cfg.picker_config
            and cfg.picker_config.mini_picker
            and cfg.picker_config.mini_picker.content_from_bottom
          or false,
      },
    }
  end,

  commits = function(opts) -- For a PR
    opts = opts or {}
    local buffer = utils.get_current_buffer()
    if not buffer or not buffer:isPullRequest() then
      utils.error "Not in a Pull Request buffer. Cannot list commits."
      return
    end

    local repo_owner = buffer.owner
    local repo_name = buffer.name
    local pr_number = buffer.number

    local url = string.format("repos/%s/%s/pulls/%d/commits", repo_owner, repo_name, pr_number)
    utils.info("Fetching commits for PR #" .. pr_number .. "...")

    gh.run {
      args = { "api", "--paginate", url },
      cb = function(output, stderr)
        if stderr and not utils.is_blank(stderr) then
          utils.error("Error fetching commits: " .. stderr)
        elseif output then
          local commits_data = vim.json.decode(output or "[]")
          if #commits_data == 0 then
            utils.info("No commits found for PR #" .. pr_number)
            return
          end

          local items_for_picker = {}
          for _, commit_item in ipairs(commits_data) do
            local short_sha = string.sub(commit_item.sha or "unknown_sha", 1, 7)
            local first_line_message = (commit_item.commit and commit_item.commit.message or ""):match "^[^]*"
            table.insert(items_for_picker, {
              text = string.format("%s %s", short_sha, first_line_message),
              data = commit_item,
            })
          end

          local function choose_commit(selected_item)
            if selected_item and selected_item.data and selected_item.data.html_url then
              utils.open_in_browser_from_url(selected_item.data.html_url)
            elseif selected_item and selected_item.data then
              utils.warn(
                "Selected commit does not have a direct html_url: " .. (selected_item.data.sha or selected_item.text)
              )
            end
            return false
          end

          local MiniPick = _G.MiniPick
          if not MiniPick then
            utils.error "MiniPick is not loaded."
            return
          end
          local cfg = octo_config.values
          MiniPick.start {
            source = {
              items = items_for_picker,
              name = "Commits (PR #" .. pr_number .. ")",
              choose = choose_commit,
              -- preview = function(buf_id, item_to_preview) -- could show commit diffstat or full message
            },
            options = {
              content_from_bottom = cfg.picker_config
                  and cfg.picker_config.mini_picker
                  and cfg.picker_config.mini_picker.content_from_bottom
                or false,
            },
          }
        end
      end,
    }
  end,

  review_commits = function(opts) -- For selecting commit range in review
    opts = opts or {}
    local callback = opts.cb
    if not callback then
      utils.error "Callback (opts.cb) for review_commits selection is required."
      return
    end

    local current_review = reviews.get_current_review()
    if not current_review then
      utils.error "No review in progress."
      return
    end

    local repo_owner = current_review.pull_request.owner
    local repo_name = current_review.pull_request.name
    local pr_number = current_review.pull_request.number

    local url = string.format("repos/%s/%s/pulls/%d/commits", repo_owner, repo_name, pr_number)
    utils.info("Fetching commits for review selection (PR #" .. pr_number .. ")...")

    gh.run {
      args = { "api", "--paginate", url },
      cb = function(output, stderr)
        if stderr and not utils.is_blank(stderr) then
          utils.error("Error fetching review commits: " .. stderr)
        elseif output then
          local commits_data = vim.json.decode(output or "[]")

          table.insert(commits_data, 1, {
            sha = current_review.pull_request.right.commit,
            commit = {
              message = "[[ENTIRE PULL REQUEST]]",
              author = { name = "", email = "", date = "" },
            },
            parents = { { sha = current_review.pull_request.left.commit } },
            is_entire_pr_entry = true,
          })

          if #commits_data == 0 then
            utils.info("No commits found for PR #" .. pr_number .. " for review.")
            return
          end

          local items_for_picker = {}
          for _, commit_item in ipairs(commits_data) do
            local short_sha = string.sub(commit_item.sha or "unknown_sha", 1, 7)
            local first_line_message = (commit_item.commit and commit_item.commit.message or ""):match "^[^ ]*"
            table.insert(items_for_picker, {
              text = string.format("%s %s", short_sha, first_line_message),
              data = commit_item,
            })
          end

          local function choose_review_commit(selected_item)
            if selected_item and selected_item.data then
              local right_sha = selected_item.data.sha
              local left_sha
              if selected_item.data.is_entire_pr_entry then
                left_sha = selected_item.data.parents[1].sha
              elseif selected_item.data.parents and #selected_item.data.parents > 0 then
                left_sha = selected_item.data.parents[1].sha
              else
                left_sha = nil
              end
              callback(right_sha, left_sha)
            end
            return false
          end

          local MiniPick = _G.MiniPick
          if not MiniPick then
            utils.error "MiniPick is not loaded."
            return
          end
          local cfg = octo_config.values
          MiniPick.start {
            source = {
              items = items_for_picker,
              name = "Select Commit for Review (PR #" .. pr_number .. ")",
              choose = choose_review_commit,
            },
            options = {
              content_from_bottom = cfg.picker_config
                  and cfg.picker_config.mini_picker
                  and cfg.picker_config.mini_picker.content_from_bottom
                or false,
            },
          }
        end
      end,
    }
  end,

  pending_threads = function(opts)
    opts = opts or {}
    local threads = opts.threads

    if not threads or #threads == 0 then
      utils.info "No pending review threads."
      return
    end

    local items_for_picker = {}
    for _, thread_item in ipairs(threads) do
      local first_comment_body = (
        thread_item.comments and #thread_item.comments > 0 and thread_item.comments[1].body or ""
      ):match "^[^ ]*"
      table.insert(items_for_picker, {
        text = string.format(
          "%s:%d %s",
          thread_item.path,
          thread_item.line or thread_item.startLine or "N/A",
          first_comment_body
        ),
        data = thread_item,
      })
    end

    local function choose_thread(selected_item)
      if selected_item and selected_item.data then
        reviews.jump_to_pending_review_thread(selected_item.data)
      end
      return false
    end

    local MiniPick = _G.MiniPick
    if not MiniPick then
      utils.error "MiniPick is not loaded."
      return
    end
    local cfg = octo_config.values
    MiniPick.start {
      source = {
        items = items_for_picker,
        name = "Pending Review Threads",
        choose = choose_thread,
      },
      options = {
        content_from_bottom = cfg.picker_config
            and cfg.picker_config.mini_picker
            and cfg.picker_config.mini_picker.content_from_bottom
          or false,
      },
    }
  end,

  discussions = function(opts)
    opts = opts or {}
    local repo = opts.repo or utils.get_remote_name()
    if not repo then
      utils.error "Cannot determine repository for discussions."
      return
    end
    local owner, name = utils.split_repo(repo)
    local cfg = octo_config.values
    local order_by = cfg.discussions and cfg.discussions.order_by or { field = "UPDATED_AT", direction = "DESC" }

    utils.info("Fetching discussions for " .. repo .. "...")
    gh.api.graphql {
      query = queries.discussions,
      fields = {
        owner = owner,
        name = name,
        states = { "OPEN" },
        orderBy = order_by.field,
        direction = order_by.direction,
      },
      paginate = true,
      jq = ".data.repository.discussions.nodes",
      opts = {
        cb = gh.create_callback {
          success = function(output)
            local discussions_data = utils.get_flatten_pages(output)
            if #discussions_data == 0 then
              utils.info(string.format("No discussions found for %s.", repo))
              return
            end

            local items_for_picker = {}
            for _, disc_item in ipairs(discussions_data) do
              table.insert(items_for_picker, {
                text = string.format("#%d %s", disc_item.number, disc_item.title),
                data = disc_item,
                repo_full_name = repo,
              })
            end

            local function choose_discussion(selected_item)
              if selected_item and selected_item.data then
                utils.get("discussion", selected_item.data.number, selected_item.repo_full_name)
              end
              return false
            end

            local MiniPick = _G.MiniPick
            if not MiniPick then
              utils.error "MiniPick is not loaded."
              return
            end
            MiniPick.start {
              source = {
                items = items_for_picker,
                name = "Discussions (" .. repo .. ")",
                choose = choose_discussion,
              },
              options = {
                content_from_bottom = cfg.picker_config
                    and cfg.picker_config.mini_picker
                    and cfg.picker_config.mini_picker.content_from_bottom
                  or false,
              },
            }
          end,
          error = function(err)
            utils.error("Error fetching discussions: " .. err)
          end,
        },
      },
    }
  end,

  workflow_runs = function(opts)
    opts = opts or {}
    local workflow_runs_data = opts.workflow_runs
    local title = opts.title or "Workflow Runs"
    local on_select_cb = opts.on_select_cb

    if not workflow_runs_data or #workflow_runs_data == 0 then
      utils.info "No workflow runs provided."
      return
    end
    if not on_select_cb then
      utils.error "on_select_cb is required for workflow_runs picker."
      return
    end

    local items_for_picker = {}
    for _, run_item in ipairs(workflow_runs_data) do
      local conclusion_icon = ""
      if run_item.status == "COMPLETED" then
        conclusion_icon = octo_config.values.runs.icons[run_item.conclusion:lower()] or run_item.conclusion
      else
        conclusion_icon = octo_config.values.runs.icons[run_item.status:lower()] or run_item.status
      end
      local display_title = run_item.displayTitle or run_item.name or ("Run " .. run_item.id)
      local actor_login = (run_item.actor and run_item.actor.login) or "unknown"

      table.insert(items_for_picker, {
        text = string.format(
          "[%s %s] %s by %s (%s)",
          conclusion_icon,
          run_item.conclusion or run_item.status,
          display_title,
          actor_login,
          run_item.headBranch or ""
        ),
        data = run_item,
      })
    end

    local function choose_workflow_run(selected_item)
      if selected_item and selected_item.data then
        on_select_cb(selected_item.data)
      end
      return false
    end

    local MiniPick = _G.MiniPick
    if not MiniPick then
      utils.error "MiniPick is not loaded."
      return
    end
    local cfg = octo_config.values
    MiniPick.start {
      source = {
        items = items_for_picker,
        name = title,
        choose = choose_workflow_run,
      },
      options = {
        content_from_bottom = cfg.picker_config
            and cfg.picker_config.mini_picker
            and cfg.picker_config.mini_picker.content_from_bottom
          or false,
      },
    }
  end,

  actions = function(opts) -- Octo actions picker
    opts = opts or {}
    local flattened_actions = opts.flattened_actions -- Expects actions to be passed in

    if not flattened_actions or #flattened_actions == 0 then
      utils.info "No actions available."
      return
    end

    local items_for_picker = {}
    for _, action_item in ipairs(flattened_actions) do
      table.insert(items_for_picker, {
        text = action_item.object, -- 'object' usually holds the description
        data = action_item, -- Store the whole action item, which includes 'fun'
      })
    end

    local function choose_action(selected_item)
      if selected_item and selected_item.data and selected_item.data.fun then
        selected_item.data.fun() -- Execute the action's function
      end
      return false -- Stop picker after action
    end

    local MiniPick = _G.MiniPick
    if not MiniPick then
      utils.error "MiniPick is not loaded."
      return
    end
    local cfg = octo_config.values
    MiniPick.start {
      source = {
        items = items_for_picker,
        name = "Octo Actions",
        choose = choose_action,
      },
      options = {
        content_from_bottom = cfg.picker_config
            and cfg.picker_config.mini_picker
            and cfg.picker_config.mini_picker.content_from_bottom
          or false,
      },
    }
  end,

  assigned_labels = function(opts)
    opts = opts or {}
    local cb = opts.cb
    if not cb then
      utils.error "Callback (opts.cb) for assigned_labels selection is required."
      return
    end

    local buffer = utils.get_current_buffer()
    if not buffer or not (buffer:isIssue() or buffer:isPullRequest() or buffer:isDiscussion()) then
      utils.error "Not in an Issue, Pull Request, or Discussion buffer."
      return
    end

    local query_gql
    local jq_path
    local entity_type = ""

    if buffer:isIssue() then
      query_gql = graphql("issue_labels_query", buffer.owner, buffer.name, buffer.number)
      jq_path = ".data.repository.issue.labels.nodes"
      entity_type = "Issue"
    elseif buffer:isPullRequest() then
      query_gql = graphql("pull_request_labels_query", buffer.owner, buffer.name, buffer.number)
      jq_path = ".data.repository.pullRequest.labels.nodes"
      entity_type = "PR"
    elseif buffer:isDiscussion() then
      query_gql = graphql("discussion_labels_query", buffer.owner, buffer.name, buffer.number)
      jq_path = ".data.repository.discussion.labels.nodes"
      entity_type = "Discussion"
    else
      utils.error "Unsupported buffer type for assigned_labels." -- Should be caught by earlier check
      return
    end

    utils.info("Fetching assigned labels for current " .. entity_type .. "...")
    gh.api.graphql {
      query = query_gql,
      jq = jq_path,
      opts = {
        cb = gh.create_callback {
          success = function(output)
            local labels_data = vim.json.decode(output or "[]")
            if #labels_data == 0 then
              utils.info("No labels assigned to the current " .. entity_type .. ".")
              return
            end

            local items_for_picker = {}
            for _, label_item in ipairs(labels_data) do
              table.insert(items_for_picker, {
                text = label_item.name,
                data = label_item,
              })
            end

            local function choose_assigned_label(selected_item)
              if selected_item and selected_item.data then
                cb(selected_item.data) -- Execute the callback
              end
              return false
            end

            local MiniPick = _G.MiniPick
            if not MiniPick then
              utils.error "MiniPick is not loaded."
              return
            end
            local cfg = octo_config.values
            MiniPick.start {
              source = {
                items = items_for_picker,
                name = "Assigned Labels (" .. entity_type .. ")",
                choose = choose_assigned_label,
              },
              options = {
                content_from_bottom = cfg.picker_config
                    and cfg.picker_config.mini_picker
                    and cfg.picker_config.mini_picker.content_from_bottom
                  or false,
              },
            }
          end,
          error = function(err)
            utils.error("Error fetching assigned labels: " .. err)
          end,
        },
      },
    }
  end,

  project_cards = function(opts) -- Legacy: select_project_card
    opts = opts or {}
    local cb = opts.cb
    if not cb then
      utils.error "Callback (opts.cb) for project_cards selection is required."
      return
    end

    local buffer = utils.get_current_buffer()
    if not buffer or not buffer.node or not buffer.node.projectCards then
      utils.error "Cannot find project cards in the current buffer context."
      return
    end

    local cards = buffer.node.projectCards.nodes
    if not cards or #cards == 0 then
      utils.info "No project cards found for the current item."
      return
    end

    if #cards == 1 then
      cb(cards[1].id) -- Directly call cb if only one card
      return
    end

    local items_for_picker = {}
    for _, card_item in ipairs(cards) do
      table.insert(items_for_picker, {
        text = (card_item.note and string.sub(card_item.note, 1, 50) .. (#card_item.note > 50 and "..." or ""))
          or (card_item.content and card_item.content.title and string.sub(card_item.content.title, 1, 50) .. (#card_item.content.title > 50 and "..." or ""))
          or ("Card ID: " .. card_item.id),
        data = card_item,
      })
    end

    local function choose_project_card(selected_item)
      if selected_item and selected_item.data then
        cb(selected_item.data.id)
      end
      return false
    end

    local MiniPick = _G.MiniPick
    if not MiniPick then
      utils.error "MiniPick is not loaded."
      return
    end
    local cfg = octo_config.values
    MiniPick.start {
      source = {
        items = items_for_picker,
        name = "Select Project Card",
        choose = choose_project_card,
      },
      options = {
        content_from_bottom = cfg.picker_config
            and cfg.picker_config.mini_picker
            and cfg.picker_config.mini_picker.content_from_bottom
          or false,
      },
    }
  end,

  project_columns = function(opts) -- Legacy: select_target_project_column
    opts = opts or {}
    local cb = opts.cb
    if not cb then
      utils.error "Callback (opts.cb) for project_columns selection is required."
      return
    end

    local buffer = utils.get_current_buffer()
    if not buffer then
      utils.error "Cannot determine current buffer for project context."
      return
    end

    local owner = buffer.owner
    local name = buffer.name
    local viewer_login = vim.g.octo_viewer or owner

    utils.info "Fetching projects..."
    gh.api.graphql {
      query = queries.projects_query,
      fields = { owner = owner, name = name, viewerLogin = viewer_login, resourceOwnerLogin = owner },
      paginate = true,
      jq = ".data",
      opts = {
        cb = gh.create_callback {
          success = function(output_projects)
            local resp_projects = vim.json.decode(output_projects or "{}")
            local projects = {}
            if resp_projects.data then
              if resp_projects.data.user and resp_projects.data.user.projects then
                vim.list_extend(projects, resp_projects.data.user.projects.nodes or {})
              end
              if resp_projects.data.repository and resp_projects.data.repository.projects then
                vim.list_extend(projects, resp_projects.data.repository.projects.nodes or {})
              end
              if resp_projects.data.organization and resp_projects.data.organization.projects then
                vim.list_extend(projects, resp_projects.data.organization.projects.nodes or {})
              end
            end

            if #projects == 0 then
              utils.info(string.format("No projects found for %s/%s.", owner, name))
              return
            end

            local project_items_for_picker = {}
            for _, proj in ipairs(projects) do
              table.insert(project_items_for_picker, { text = proj.name, data = proj })
            end

            local function choose_project_for_column_selection(selected_project_item)
              if
                not (
                  selected_project_item
                  and selected_project_item.data
                  and selected_project_item.data.columns
                  and selected_project_item.data.columns.nodes
                )
              then
                utils.info "Selected project has no columns or data is missing."
                return true
              end

              local column_items_for_picker = {}
              for _, col in ipairs(selected_project_item.data.columns.nodes) do
                table.insert(column_items_for_picker, { text = col.name, data = col })
              end

              if #column_items_for_picker == 0 then
                utils.info("Project '" .. selected_project_item.data.name .. "' has no columns.")
                return true
              end

              local function choose_column(selected_column_item)
                if selected_column_item and selected_column_item.data then
                  cb(selected_column_item.data.id)
                end
                return false
              end

              local MiniPick_Col = _G.MiniPick
              if not MiniPick_Col then
                utils.error "MiniPick is not loaded for column selection."
                return false
              end
              local cfg_col = octo_config.values
              MiniPick_Col.start {
                source = {
                  items = column_items_for_picker,
                  name = "Select Column in '" .. selected_project_item.data.name .. "'",
                  choose = choose_column,
                },
                options = {
                  content_from_bottom = cfg_col.picker_config
                      and cfg_col.picker_config.mini_picker
                      and cfg_col.picker_config.mini_picker.content_from_bottom
                    or false,
                },
              }
              return false
            end

            local MiniPick_Proj = _G.MiniPick
            if not MiniPick_Proj then
              utils.error "MiniPick is not loaded for project selection."
              return
            end
            local cfg_proj = octo_config.values
            MiniPick_Proj.start {
              source = {
                items = project_items_for_picker,
                name = "Select Project",
                choose = choose_project_for_column_selection,
              },
              options = {
                content_from_bottom = cfg_proj.picker_config
                    and cfg_proj.picker_config.mini_picker
                    and cfg_proj.picker_config.mini_picker.content_from_bottom
                  or false,
              },
            }
          end,
          error = function(err)
            utils.error("Error fetching projects: " .. err)
          end,
        },
      },
    }
  end,

  project_cards_v2 = function(opts)
    opts = opts or {}
    local cb = opts.cb
    if not cb then
      utils.error "Callback (opts.cb) for project_cards_v2 selection is required."
      return
    end

    local buffer = utils.get_current_buffer()
    if not buffer or not buffer.node or not buffer.node.projectItems then
      utils.error "Cannot find project v2 items (projectItems) in the current buffer context."
      return
    end

    local cards_v2 = buffer.node.projectItems.nodes
    if not cards_v2 or #cards_v2 == 0 then
      utils.info "No project v2 items found for the current item."
      return
    end

    if #cards_v2 == 1 then
      local node = cards_v2[1]
      if node.project and node.project.id and node.id then
        cb(node.project.id, node.id)
      else
        utils.error "Single project v2 item found, but is missing project.id or item.id."
      end
      return
    end

    utils.error "Multiple project v2 cards found. This picker currently supports only single card assignment directly or selection when only one card is present."
  end,

  project_columns_v2 = function(opts)
    opts = opts or {}
    local cb = opts.cb
    if not cb then
      utils.error "Callback (opts.cb) for project_columns_v2 selection is required."
      return
    end

    local buffer = utils.get_current_buffer()
    if not buffer then
      utils.error "Cannot determine current buffer for project v2 context."
      return
    end

    local owner = buffer.owner
    local name = buffer.name
    local viewer_login = vim.g.octo_viewer or owner

    utils.info "Fetching projects (v2)..."
    gh.api.graphql {
      query = queries.projects_v2_query,
      fields = { owner = owner, name = name, viewerLogin = viewer_login, resourceOwnerLogin = owner },
      paginate = true,
      jq = ".data",
      opts = {
        cb = gh.create_callback {
          success = function(output_projects_v2)
            local resp_projects_v2 = vim.json.decode(output_projects_v2 or "{}")
            local projects_v2_list = {}
            if resp_projects_v2.data then
              local sources = {
                resp_projects_v2.data.user
                    and resp_projects_v2.data.user.projectsV2
                    and resp_projects_v2.data.user.projectsV2.nodes
                  or {},
                resp_projects_v2.data.repository
                    and resp_projects_v2.data.repository.projectsV2
                    and resp_projects_v2.data.repository.projectsV2.nodes
                  or {},
                resp_projects_v2.data.organization
                    and resp_projects_v2.data.organization.projectsV2
                    and resp_projects_v2.data.organization.projectsV2.nodes
                  or {},
              }
              local project_ids_seen = {}
              for _, source_list in ipairs(sources) do
                for _, proj in ipairs(source_list) do
                  if not project_ids_seen[proj.id] then
                    table.insert(projects_v2_list, proj)
                    project_ids_seen[proj.id] = true
                  end
                end
              end
            end

            if #projects_v2_list == 0 then
              utils.info(string.format("No projects (v2) found for %s/%s.", owner, name))
              return
            end

            local project_items_for_picker = {}
            for _, proj in ipairs(projects_v2_list) do
              table.insert(project_items_for_picker, { text = proj.title, data = proj })
            end

            local function choose_project_v2_for_column(selected_project_item)
              if not (selected_project_item and selected_project_item.data) then
                utils.info "No project v2 selected or data missing."
                return true
              end

              local project_data = selected_project_item.data
              local target_field_node = nil
              if project_data.fields and project_data.fields.nodes then
                for _, field_node in ipairs(project_data.fields.nodes) do
                  if field_node.dataType == "SINGLE_SELECT" and field_node.options then
                    if field_node.name == "Status" then
                      target_field_node = field_node
                      break
                    elseif not target_field_node then
                      target_field_node = field_node
                    end
                  end
                end
              end

              if not target_field_node or not target_field_node.options or #target_field_node.options == 0 then
                utils.error(
                  "Could not find a suitable 'Status' column or single-select field with options in project '"
                    .. project_data.title
                    .. "'."
                )
                return true
              end

              local column_options_for_ui_select = {}
              for _, opt in ipairs(target_field_node.options) do
                table.insert(column_options_for_ui_select, opt.name)
              end

              vim.ui.select(column_options_for_ui_select, {
                prompt = "Select '" .. target_field_node.name .. "' value for project '" .. project_data.title .. "': ",
                format_item = function(item_name)
                  return item_name
                end,
              }, function(value_name)
                if value_name then
                  local selected_option_id = nil
                  for _, opt in ipairs(target_field_node.options) do
                    if opt.name == value_name then
                      selected_option_id = opt.id
                      break
                    end
                  end
                  if selected_option_id then
                    cb(project_data.id, target_field_node.id, selected_option_id)
                  else
                    utils.error("Could not find ID for selected option: " .. value_name)
                  end
                end
              end)
              return false
            end

            local MiniPick_Proj_v2 = _G.MiniPick
            if not MiniPick_Proj_v2 then
              utils.error "MiniPick is not loaded for project v2 selection."
              return
            end
            local cfg_proj_v2 = octo_config.values
            MiniPick_Proj_v2.start {
              source = {
                items = project_items_for_picker,
                name = "Select Project (v2)",
                choose = choose_project_v2_for_column,
              },
              options = {
                content_from_bottom = cfg_proj_v2.picker_config
                    and cfg_proj_v2.picker_config.mini_picker
                    and cfg_proj_v2.picker_config.mini_picker.content_from_bottom
                  or false,
              },
            }
          end,
          error = function(err)
            utils.error("Error fetching projects (v2): " .. err)
          end,
        },
      },
    }
  end,
}

return M
