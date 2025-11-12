---@diagnostic disable
local constants = require "octo.constants"
local context = require "octo.context"
local navigation = require "octo.navigation"
local gh = require "octo.gh"
local headers = require "octo.gh.headers"
local graphql = require "octo.gh.graphql"
local queries = require "octo.gh.queries"
local mutations = require "octo.gh.mutations"
local picker = require "octo.picker"
local reviews = require "octo.reviews"
local window = require "octo.ui.window"
local writers = require "octo.ui.writers"
local utils = require "octo.utils"
local config = require "octo.config"
local vim = vim

-- a global variable where command handlers can access the details of the last
-- command ran.
--
-- this came into existence since some commands like "comment add" need to
-- understand the line range the comment should be created on.
-- this is problematic without the command options as you exit visual mode when
-- enterting the command line.
---@type vim.api.keyset.create_user_command.command_args?
OctoLastCmdOpts = nil

local M = {}

local function merge_tables(t1, t2)
  local result = vim.deepcopy(t1)
  for k, v in pairs(t2) do
    if type(v) == "table" and type(result[k]) == "table" then
      result[k] = merge_tables(result[k], v)
    else
      result[k] = v
    end
  end
  return result
end

function M.setup()
  vim.api.nvim_create_user_command("Octo", function(opts)
    OctoLastCmdOpts = opts
    require("octo.commands").octo(unpack(opts.fargs))
    OctoLastCmdOpts = nil
  end, { complete = require("octo.completion").octo_command_complete, nargs = "*", range = true })
  local conf = config.values

  local card_commands
  if conf.default_to_projects_v2 then
    card_commands = {
      set = function()
        M.set_project_v2_card()
      end,
      remove = function()
        M.remove_project_v2_card()
      end,
    }
  end

  -- supported commands
  M.commands = {
    workflow = {
      edit = function()
        local workflow = require "octo.workflow_runs"
        local current_wf = workflow.current_wf

        if current_wf then
          workflow.edit(current_wf.workflowName)
          return
        end

        workflow.workflow_list {
          cb = workflow.edit,
        }
      end,
      list = function()
        local workflow = require "octo.workflow_runs"
        workflow.workflow_list {
          cb = workflow.edit,
        }
      end,
    },
    run = {
      list = function()
        local function co_wrapper()
          require("octo.workflow_runs").list()
        end

        local co = coroutine.create(co_wrapper)
        coroutine.resume(co)
      end,
    },
    actions = function()
      M.actions()
    end,
    search = function(...)
      M.search(...)
    end,
    discussion = {
      browser = function()
        navigation.open_in_browser()
      end,
      reload = function()
        M.reload { verbose = true }
      end,
      mark = function()
        M.mark()
      end,
      unmark = function()
        M.mark { undo = true }
      end,
      list = function(repo, ...)
        local opts = M.process_varargs(repo, ...)
        picker.discussions(opts)
      end,
      category = context.within_discussion(function(buffer)
        local node = buffer:discussion()
        require("octo.discussions").change_category {
          repo = node.repository.nameWithOwner,
          current_category = node.category.name,
          discussion_id = node.id,
        }
      end),
      create = function(repo, ...)
        local opts = M.process_varargs(repo, ...)

        if not opts.repo then
          utils.error "No repo found"
          return
        end

        require("octo.discussions").create(opts)
      end,
      reopen = context.within_discussion(function(buffer)
        gh.api.graphql {
          query = mutations.reopen_discussion,
          fields = { discussion_id = buffer:discussion().id },
          jq = ".data.reopenDiscussion.discussion.id",
          opts = {
            cb = gh.create_callback {
              success = function(response_id)
                if response_id == buffer:discussion().id then
                  utils.info "Discussion reopened"
                end
              end,
            },
          },
        }
      end),
      search = function(...)
        local args = table.pack(...)
        local prompt = table.concat(args, " ")
        local repo = utils.get_remote_name()
        prompt = "repo:" .. repo .. " " .. prompt
        picker.search { prompt = prompt, type = "DISCUSSION" }
      end,
      close = context.within_discussion(function(buffer)
        --https://docs.github.com/en/graphql/reference/enums#discussionclosereason
        local reasons = {
          "Duplicate",
          "Outdated",
          "Resolved",
        }
        vim.ui.select(reasons, {
          prompt = "Select a reason for closing the discussion:",
        }, function(reason)
          if not reason then
            return
          end

          gh.api.graphql {
            query = mutations.close_discussion,
            fields = { discussion_id = buffer:discussion().id, reason = string.upper(reason) },
            jq = ".data.closeDiscussion.discussion.id",
            opts = {
              cb = gh.create_callback {
                success = function(response_id)
                  if response_id == buffer:discussion().id then
                    utils.info("Discussion closed with reason: " .. reason)
                  end
                end,
              },
            },
          }
        end)
      end),
    },
    type = {
      add = context.within_issue(function(buffer)
        local owner, repo = utils.split_repo(buffer.repo)

        gh.api.graphql {
          query = queries.issue_types,
          jq = ".data.repository.issueTypes.nodes",
          F = {
            owner = owner,
            name = repo,
          },
          opts = {
            cb = gh.create_callback {
              success = function(response)
                if utils.is_blank(response) then
                  utils.error("No issue types found for " .. buffer.repo)
                  return
                end

                ---@type octo.IssueType[]
                local types = vim.json.decode(response)
                if #types == 0 then
                  utils.error("No issue types found for " .. buffer.repo)
                  return
                end

                vim.ui.select(types, {
                  prompt = "Select an issue type to add:",
                  ---@param item octo.IssueType
                  format_item = function(item)
                    return item.name
                  end,
                }, function(selected_type)
                  if not selected_type then
                    return
                  end

                  gh.api.graphql {
                    query = mutations.update_issue_issue_type,
                    F = {
                      issue_id = buffer:issue().id,
                      issue_type_id = selected_type.id,
                    },
                    opts = {
                      cb = gh.create_callback {
                        success = function(_)
                          utils.info("Issue type added: " .. selected_type.name)
                        end,
                      },
                    },
                  }
                end)
              end,
            },
          },
        }
      end),
      remove = context.within_issue(function(buffer)
        local current_type = buffer:issue().issueType

        if not current_type or utils.is_blank(current_type) then
          utils.error "No issue type to remove"
          return
        end

        gh.api.graphql {
          query = mutations.update_issue_issue_type,
          F = {
            issue_id = buffer:issue().id,
          },
          opts = {
            cb = gh.create_callback {
              success = function(_)
                utils.info("Issue type removed: " .. current_type.name)
              end,
            },
          },
        }
      end),
    },
    milestone = {
      list = function(repo, ...)
        local opts = M.process_varargs(repo, ...)
        opts.cb = function(item)
          local url = item.url
          utils.info("Opening milestone in browser: " .. url)
          navigation.open_in_browser_raw(url)
        end
        picker.milestones(opts)
      end,
      add = function(milestoneTitle)
        local buffer = utils.get_current_buffer()
        if not buffer then
          utils.error "No buffer found"
          return
        end

        if not utils.is_blank(milestoneTitle) then
          utils.add_milestone(buffer:isIssue(), buffer.number, milestoneTitle)
          return
        end

        local opts = {}
        opts.cb = function(item)
          utils.add_milestone(buffer:isIssue(), buffer.number, item.title)
        end
        picker.milestones(opts)
      end,
      remove = context.within_issue_or_pr(function(buffer)
        local node = buffer:isIssue() and buffer:issue() or buffer:pullRequest()
        local milestone = node.milestone
        if utils.is_blank(milestone) then
          utils.error "No milestone to remove"
          return
        end

        utils.remove_milestone(buffer:isIssue(), buffer.number)
      end),
      create = function(milestoneTitle)
        if utils.is_blank(milestoneTitle) then
          vim.fn.inputsave()
          milestoneTitle = vim.fn.input "Enter milestone title: "
          vim.fn.inputrestore()
        end

        vim.fn.inputsave()
        local description = vim.fn.input "Enter milestone description: "
        vim.fn.inputrestore()

        utils.create_milestone(milestoneTitle, description)
      end,
    },
    parent = {
      edit = context.within_issue(function(buffer)
        local parent = buffer:issue().parent

        if utils.is_blank(parent) then
          utils.error "No parent issue found"
          return
        end

        local uri = string.format("octo://%s/issue/%s", buffer.repo, parent.number)
        vim.cmd.edit(uri)
      end),
      remove = context.within_issue(function(buffer)
        local parent = buffer.issue().parent

        if utils.is_blank(parent) then
          utils.error "No parent issue found"
          return
        end

        gh.api.graphql {
          query = mutations.remove_subissue,
          fields = {
            parent_id = parent.id,
            child_id = buffer.issue().id,
          },
          jq = ".data.removeSubIssue.subIssue.id",
          opts = {
            cb = gh.create_callback {
              success = function(response_id)
                if response_id == buffer:issue().id then
                  utils.info "Issue removed as sub-issue"
                end
              end,
            },
          },
        }
      end),
      add = context.within_issue(function(buffer)
        local opts = {}
        opts.cb = function(selected)
          gh.api.graphql {
            query = mutations.add_subissue,
            fields = {
              parent_id = selected.obj.id,
              child_id = buffer:issue().id,
            },
            jq = ".data.addSubIssue.subIssue.id",
            opts = {
              cb = gh.create_callback {
                success = function(response_id)
                  if response_id == buffer:issue().id then
                    utils.info "Issue added as sub-issue"
                  end
                end,
              },
            },
          }
        end

        picker.issues(opts)
      end),
    },
    issue = {
      copilot = context.within_issue(function(buffer)
        gh.issue.edit {
          buffer:issue().number,
          add_assignee = "@copilot",
          opts = {
            cb = function(_, _, exit_code)
              if exit_code == 0 then
                utils.info "GitHub Copilot assigned to the Issue"
              else
                utils.error "Failed to assign GitHub Copilot to the Issue"
              end
            end,
          },
        }
      end),
      create = function(repo)
        M.create_issue(repo)
      end,
      edit = function(...)
        utils.get_issue(...)
      end,
      close = function(stateReason)
        stateReason = stateReason or "CLOSED"
        M.change_state(stateReason)
      end,
      unpin = context.within_issue(function(buffer)
        M.pin_issue { obj = buffer:issue(), add = false }
      end),
      pin = context.within_issue(function(buffer)
        M.pin_issue { obj = buffer:issue(), add = true }
      end),
      develop = function(repo, ...)
        local buffer = utils.get_current_buffer()

        if buffer and buffer:isIssue() then
          utils.develop_issue(buffer.repo, buffer:issue().number, repo)
        else
          local opts = M.process_varargs(repo, ...)
          opts.cb = function(selected)
            utils.develop_issue(selected.repo, selected.obj.number, repo)
          end
          picker.issues(opts)
        end
      end,
      reopen = function()
        M.change_state "OPEN"
      end,
      list = function(repo, ...)
        local opts = M.process_varargs(repo, ...)
        picker.issues(opts)
      end,
      search = function(repo, ...)
        local opts = M.process_varargs(repo, ...)
        if utils.is_blank(opts.repo) then
          utils.error "Cannot find repo"
          return
        end
        local prompt = "is:issue "
        for k, v in pairs(opts) do
          prompt = prompt .. k .. ":" .. v .. " "
        end
        opts.prompt = prompt
        picker.search(opts)
      end,
      reload = function()
        M.reload { verbose = true }
      end,
      browser = function()
        navigation.open_in_browser()
      end,
      url = function()
        M.copy_url()
      end,
    },
    pr = {
      copilot = context.within_pr(function(buffer)
        gh.pr.edit {
          buffer:pullRequest().number,
          add_assignee = "@copilot",
          opts = {
            cb = function(_, _, exit_code)
              if exit_code == 0 then
                utils.info "GitHub Copilot assigned to the Pull Request"
              else
                utils.error "Failed to assign GitHub Copilot to the Pull Request"
              end
            end,
          },
        }
      end),
      edit = function(...)
        utils.get_pull_request(...)
      end,
      runs = context.within_pr(function(buffer)
        require("octo.workflow_runs").list { branch = buffer:pullRequest().headRefName }
      end),
      close = function()
        M.change_state "CLOSED"
      end,
      reopen = function()
        M.change_state "OPEN"
      end,
      list = function(repo, ...)
        local opts = M.process_varargs(repo, ...)
        picker.prs(opts)
      end,
      checkout = function()
        local buffer = utils.get_current_buffer()

        if not buffer or not buffer:isPullRequest() then
          picker.prs {
            cb = function(selected)
              utils.checkout_pr(selected.obj.number)
            end,
          }
          return
        end
        if not utils.in_pr_repo() then
          return
        end
        utils.checkout_pr(buffer:pullRequest().number)
      end,
      create = function(...)
        M.create_pr(...)
      end,
      commits = context.within_pr(function(buffer)
        picker.commits(buffer)
      end),
      changes = context.within_pr(function(buffer)
        picker.changed_files(buffer)
      end),
      diff = function()
        M.show_pr_diff()
      end,
      merge = function(...)
        M.merge_pr(...)
      end,
      checks = context.within_pr(M.pr_checks),
      ready = context.within_pr(function(buffer)
        M.gh_pr_ready { pr = buffer:pullRequest(), bufnr = buffer.bufnr, undo = false }
      end),
      draft = context.within_pr(function(buffer)
        M.gh_pr_ready { pr = buffer:pullRequest(), bufnr = buffer.bufnr, undo = true }
      end),
      search = function(repo, ...)
        local opts = M.process_varargs(repo, ...)
        if utils.is_blank(opts.repo) then
          utils.error "Cannot find repo"
          return
        end
        local prompt = "is:pr "
        for k, v in pairs(opts) do
          prompt = prompt .. k .. ":" .. v .. " "
        end
        opts.prompt = prompt
        opts.search_prs = true
        picker.search(opts)
      end,
      reload = function()
        M.reload { verbose = true }
      end,
      browser = function()
        navigation.open_in_browser()
      end,
      url = function()
        M.copy_url()
      end,
      sha = M.copy_sha,
      update = context.within_pr(function(buffer)
        gh.pr.update_branch {
          buffer:pullRequest().number,
          repo = buffer:pullRequest().baseRepository.nameWithOwner,
          opts = { cb = gh.create_callback {} },
        }
      end),
    },
    release = {
      notes = function(tag_name)
        local repo = utils.get_remote_name()
        if utils.is_blank(tag_name) then
          local latest_release = gh.release.list {
            exclude_drafts = true,
            exclude_pre_releases = true,
            limit = 1,
            repo = repo,
            json = "tagName",
            jq = ".[0].tagName",
            opts = { mode = "sync" },
          }
          local prompt
          if utils.is_blank(latest_release) then
            prompt = "Enter tag name: "
          else
            prompt = "Enter tag name (latest release: " .. latest_release .. "): "
          end
          tag_name = utils.input { prompt = prompt }
        end

        gh.api.post {
          "/repos/{repo}/releases/generate-notes",
          format = { repo = repo },
          F = { tag_name = tag_name },
          jq = ".body",
          opts = {
            cb = gh.create_callback {
              success = utils.put_text_under_cursor,
            },
          },
        }
      end,
    },
    repo = {
      search = function(...)
        local args = table.pack(...)
        local prompt = table.concat(args, " ")
        picker.search {
          type = "REPOSITORY",
          prompt = prompt,
        }
      end,
      list = function(login)
        local opts = { login = login }

        if not opts.login then
          if vim.g.octo_viewer then
            opts.login = vim.g.octo_viewer
          else
            local remote_hostname = utils.get_remote_host()
            opts.login = gh.get_user_name(remote_hostname)
          end
        end

        picker.repos(opts)
      end,
      view = function(repo)
        if repo == nil and utils.cwd_is_git() then
          repo = utils.get_remote_name()
          utils.get_repo(nil, repo)
        elseif repo == nil then
          utils.error "Argument for repo name is required"
        else
          utils.get_repo(nil, repo)
        end
      end,
      fork = function()
        utils.fork_repo()
      end,
      browser = function()
        navigation.open_in_browser()
      end,
      url = function()
        M.copy_url()
      end,
    },
    review = {
      browse = function()
        reviews.browse_review()
      end,
      start = function()
        reviews.start_review()
      end,
      resume = function()
        reviews.resume_review()
      end,
      comments = context.within_review(function(current_review)
        current_review:show_pending_comments()
      end),
      submit = function()
        reviews.submit_review()
      end,
      discard = function()
        reviews.discard_review()
      end,
      close = function()
        if reviews.get_current_review() then
          reviews.get_current_review().layout:close()
        else
          utils.error "Please start or resume a review first"
        end
      end,
      commit = context.within_review(function(current_review)
        picker.review_commits(current_review, function(left, right)
          current_review:focus_commit(left, right)
        end)
      end),
      thread = function()
        require("octo.reviews.thread-panel").show_review_threads(true)
      end,
    },
    gist = {
      list = function(...)
        local args = table.pack(...)
        local opts = {}
        for i = 1, args.n do
          local kv = vim.split(args[i], "=")
          opts[kv[1]] = kv[2]
        end
        picker.gists(opts)
      end,
    },
    thread = {
      resolve = function()
        M.resolve_thread()
      end,
      unresolve = function()
        M.unresolve_thread()
      end,
    },
    comment = {
      add = function()
        local current_review = reviews.get_current_review()
        if current_review and utils.in_diff_window() then
          -- if we have a current_review but no id, we are in browse mode.
          -- for now, we cannot create comments.
          -- TODO: implement 'non-review' commits here, which adds a diff commit
          -- but outside of a review.
          if current_review.id == -1 then
            utils.error "Please start or resume a review first"
            return
          end
          current_review:add_comment(false)
        else
          M.add_pr_issue_or_review_thread_comment()
        end
      end,
      suggest = context.within_review(function(current_review)
        current_review:add_comment(true)
      end),
      reply = M.add_pr_issue_or_review_thread_comment_reply,
      url = function()
        local buffer = utils.get_current_buffer()

        if not buffer then
          return
        end

        local comment = buffer:get_comment_at_cursor()
        if not comment then
          utils.error "The cursor does not seem to be located at any comment"
          return
        end

        gh.api.graphql {
          query = queries.comment_url,
          f = { id = comment.id },
          jq = ".data.node.url",
          opts = { cb = gh.create_callback { success = utils.copy_url } },
        }
      end,
      delete = function()
        M.delete_comment()
      end,
    },
    label = {
      create = function(label)
        M.create_label(label)
      end,
      add = function(label)
        M.add_label(label)
      end,
      remove = function(label)
        M.remove_label(label)
      end,
      edit = function(label)
        --- Get the description of a label
        --- @param search string
        --- @return table label_info
        local function get_label_info(opts)
          local item = gh.label.list {
            json = "name,description",
            search = opts.search,
            jq = ".[0]",
            opts = {
              mode = "sync",
            },
          }
          if item == "" then
            return {}
          end

          return vim.json.decode(item)
        end

        --- Change the name or description of a label
        --- @param label string
        --- @param kind string
        --- @param current_value string
        local function change_label_info(label, kind, current_value)
          vim.ui.input({
            prompt = "New " .. kind .. " for " .. label .. ": ",
            default = current_value,
          }, function(new_value)
            if utils.is_blank(new_value) then
              new_value = current_value
            end

            new_value = vim.fn.trim(new_value)

            if new_value == current_value then
              utils.info("No changes made to " .. kind .. " for " .. label)
              return
            end

            local opts = { label }
            opts[kind] = new_value
            gh.label.edit(opts)

            utils.info("Updated " .. kind .. " for " .. label .. " to " .. new_value)
          end)
        end

        local function cb(name)
          local info = get_label_info {
            search = name,
          }

          if utils.is_blank(info) then
            utils.error("Nothing found for " .. name)
            return
          end

          vim.ui.select(
            { "name", "description" },
            { prompt = "Edit name or description of label: " .. info.name },
            function(kind)
              if utils.is_blank(kind) then
                return
              end

              change_label_info(info.name, kind, info[kind])
            end
          )
        end

        if utils.is_blank(label) then
          picker.labels {
            cb = function(labels)
              if #labels ~= 1 then
                utils.error "Please select a single label"
                return
              end

              cb(labels[1].name)
            end,
          }
        else
          cb(label)
        end
      end,
      delete = function(label)
        local function delete_labels(labels)
          for _, label in ipairs(labels) do
            if vim.fn.confirm("Delete label: " .. label.name .. "?", "&Yes\n&No", 2) == 1 then
              gh.label.delete {
                label.name,
                yes = true,
                opts = {
                  cb = gh.create_callback {
                    success = function()
                      utils.info("Deleted label: " .. label.name)
                    end,
                  },
                },
              }
            else
              utils.info("Skipped deleting label: " .. label.name)
            end
          end
        end

        local function delete_labels_callback(labels)
          if #labels == 0 then
            utils.info "Nothing to delete"
            return
          end

          delete_labels(labels)
        end

        if utils.is_blank(label) then
          picker.labels {
            cb = delete_labels_callback,
          }
        else
          delete_labels { { name = label } }
        end
      end,
    },
    assignee = {
      add = function(...)
        M.add_user("assignee", { ... })
      end,
      remove = function(login)
        M.remove_assignee(login)
      end,
    },
    reviewer = {
      add = function(...)
        M.add_user("reviewer", { ... })
      end,
      remove = function(login)
        M.remove_reviewer(login)
      end,
    },
    reaction = {
      thumbs_up = function()
        M.reaction_action "THUMBS_UP"
      end,
      ["+1"] = function()
        M.reaction_action "THUMBS_UP"
      end,
      thumbs_down = function()
        M.reaction_action "THUMBS_DOWN"
      end,
      ["-1"] = function()
        M.reaction_action "THUMBS_DOWN"
      end,
      eyes = function()
        M.reaction_action "EYES"
      end,
      laugh = function()
        M.reaction_action "LAUGH"
      end,
      confused = function()
        M.reaction_action "CONFUSED"
      end,
      hooray = function()
        M.reaction_action "HOORAY"
      end,
      party = function()
        M.reaction_action "HOORAY"
      end,
      tada = function()
        M.reaction_action "HOORAY"
      end,
      rocket = function()
        M.reaction_action "ROCKET"
      end,
      heart = function()
        M.reaction_action "HEART"
      end,
    },
    card = card_commands,
    cardv2 = {
      set = function(...)
        M.set_project_v2_card()
      end,
      remove = function()
        M.remove_project_v2_card()
      end,
    },
    notification = {
      list = function(repo)
        local opts = {}

        if repo then
          opts.repo = repo
        elseif config.values.notifications.current_repo_only then
          opts.repo = utils.get_remote_name()
        end

        picker.notifications(opts)
      end,
    },
  }

  setmetatable(M.commands.pr, {
    __call = function(_)
      utils.get_pull_request_for_current_branch(function(pr)
        vim.cmd("e " .. utils.get_pull_request_uri(pr.number, pr.repo))
      end)
    end,
  })

  setmetatable(M.commands.review, {
    __call = function(_)
      reviews.start_or_resume_review()
    end,
  })

  setmetatable(M.commands.notification, {
    __call = function(_)
      picker.notifications()
    end,
  })

  local user_defined_commands = config.values.commands
  M.commands = merge_tables(M.commands, user_defined_commands)
end

function M.process_varargs(repo, ...)
  local args = table.pack(...)
  if utils.is_blank(repo) then
    repo = utils.get_remote_name()
  elseif string.find(repo, ":") or string.find(repo, "=") then
    args.n = args.n + 1
    table.insert(args, 1, repo)
    repo = utils.get_remote_name()
  elseif #vim.split(repo, "/") ~= 2 then
    table.insert(args, repo)
    args.n = args.n + 1
    repo = utils.get_remote_name()
  end
  local opts = {}
  for i = 1, args.n do
    local kv = vim.split(args[i], "=")
    if #kv == 2 then
      opts[kv[1]] = kv[2]
    else
      kv = vim.split(args[i], ":")
      if #kv == 2 then
        opts[kv[1]] = kv[2]
      end
    end
  end
  if not opts.repo then
    opts.repo = repo
  end
  return opts
end

function M.octo(object, action, ...)
  if not object then
    if config.values.enable_builtin then
      M.commands.actions()
    else
      utils.error "Missing arguments"
    end
    return
  end
  local o = M.commands[object]
  if not o then
    local repo, number, kind = utils.parse_url(object)
    if repo and number and kind == "issue" then
      utils.get_issue(number, repo)
    elseif repo and number and kind == "pull" then
      utils.get_pull_request(number, repo)
    elseif repo and number and kind == "discussion" then
      utils.get_discussion(number, repo)
    else
      utils.error("Incorrect argument: " .. object)
      return
    end
  else
    if type(o) == "function" then
      if object == "search" then
        o(action, ...)
      else
        o(...)
      end
      return
    end

    local a = o[action] or o
    if not a then
      utils.error(action and "Incorrect action: " .. action or "No action specified")
      return
    end

    res = pcall(a, ...)
    if not res then
      utils.error(action and "Failed action: " .. action)
      return
    end
  end
end

--- Adds a new comment to an issue/PR or a review thread
function M.add_pr_issue_or_review_thread_comment(body)
  body = body or " "
  local buffer = utils.get_current_buffer()

  if not buffer then
    return
  end

  local comment_kind
  local comment = {
    id = -1,
    author = { login = vim.g.octo_viewer },
    createdAt = os.date "!%FT%TZ",
    body = body,
    viewerCanUpdate = true,
    viewerCanDelete = true,
    viewerDidAuthor = true,
    reactionGroups = {
      { content = "THUMBS_UP", users = { totalCount = 0 } },
      { content = "THUMBS_DOWN", users = { totalCount = 0 } },
      { content = "LAUGH", users = { totalCount = 0 } },
      { content = "HOORAY", users = { totalCount = 0 } },
      { content = "CONFUSED", users = { totalCount = 0 } },
      { content = "HEART", users = { totalCount = 0 } },
      { content = "ROCKET", users = { totalCount = 0 } },
      { content = "EYES", users = { totalCount = 0 } },
    },
  }

  local _thread = buffer:get_thread_at_cursor()
  if not utils.is_blank(_thread) and buffer:isReviewThread() then
    comment_kind = "PullRequestReviewComment"

    -- are we trying to add a review comment while in 'review browse' mode?
    local current_review = reviews.get_current_review()
    if current_review == nil or current_review.id == -1 then
      utils.error "Please start or resume a review first"
      return
    end

    comment.pullRequestReview = { id = current_review.id }
    comment.state = "PENDING"
    comment.replyTo = _thread.replyTo
    comment.replyToRest = _thread.replyToRest
  elseif not utils.is_blank(_thread) and not buffer:isReviewThread() then
    comment_kind = "PullRequestComment"
    comment.state = ""
    comment.replyTo = _thread.replyTo
    comment.replyToRest = _thread.replyToRest
  elseif utils.is_blank(_thread) and not buffer:isReviewThread() then
    comment_kind = buffer:isDiscussion() and "DiscussionComment" or "IssueComment"
  elseif utils.is_blank(_thread) and buffer:isReviewThread() then
    utils.error "Error adding a comment to a review thread"
  end

  if comment_kind == "IssueComment" then
    writers.write_comment(buffer.bufnr, comment, comment_kind)
    vim.cmd [[normal Gk]]
    vim.cmd [[startinsert]]
  elseif comment_kind == "DiscussionComment" then
    local comment_under_cursor = buffer:get_comment_at_cursor()
    if not utils.is_blank(comment_under_cursor) and vim.fn.confirm("Reply to comment?", "&Yes\n&No", 2) == 1 then
      comment.replyTo = not utils.is_blank(comment_under_cursor.replyTo) and comment_under_cursor.replyTo.id
        or comment_under_cursor.id
      vim.api.nvim_buf_set_lines(
        buffer.bufnr,
        comment_under_cursor.bufferEndLine,
        comment_under_cursor.bufferEndLine,
        false,
        { "x", "x", "x", "x" }
      )
      writers.write_comment(buffer.bufnr, comment, comment_kind, comment_under_cursor.bufferEndLine + 1)
      vim.fn.execute(":" .. comment_under_cursor.bufferEndLine + 3)
      vim.cmd [[startinsert]]
    else
      writers.write_comment(buffer.bufnr, comment, comment_kind)
      vim.cmd [[normal Gk]]
      vim.cmd [[startinsert]]
    end
  elseif comment_kind == "PullRequestReviewComment" or comment_kind == "PullRequestComment" then
    vim.api.nvim_buf_set_lines(
      buffer.bufnr,
      _thread.bufferEndLine,
      _thread.bufferEndLine,
      false,
      { "x", "x", "x", "x" }
    )
    writers.write_comment(buffer.bufnr, comment, comment_kind, _thread.bufferEndLine + 1)
    vim.fn.execute(":" .. _thread.bufferEndLine + 3)
    vim.cmd [[startinsert]]
  end

  -- drop undo history
  utils.clear_history()
end

local format_reply = function(body)
  local lines = vim.split(body, "\n")
  local reply = ""
  for _, line in ipairs(lines) do
    reply = reply .. "> " .. line .. "\n"
  end
  reply = reply .. "\n"

  return reply
end

M.add_pr_issue_or_review_thread_comment_reply = function()
  local buffer = utils.get_current_buffer()

  if not buffer then
    return
  end

  local comment = buffer:get_comment_at_cursor()
  if not comment then
    utils.error "The cursor does not seem to be located at any comment"
    return
  end

  local reply_body = format_reply(comment.body)
  M.add_pr_issue_or_review_thread_comment(reply_body)

  -- Position cursor after the quoted content for replies
  vim.schedule(function()
    local current_line = vim.api.nvim_win_get_cursor(0)[1]
    local lines = vim.api.nvim_buf_get_lines(buffer.bufnr, current_line - 10, current_line + 5, false)

    -- Find the last line with quoted content and position cursor after it
    for i = #lines, 1, -1 do
      local line = lines[i]
      if line and line:match "^>" then
        -- Found last quoted line, position cursor at the end and create new line for response
        local target_line = current_line - 10 + i
        vim.api.nvim_win_set_cursor(0, { target_line, #line })
        vim.cmd [[startinsert!]]
        -- Add two newlines to create space for typing the response
        vim.api.nvim_feedkeys("\n\n", "n", false)
        return
      end
    end
  end)
end

function M.delete_comment()
  local buffer = utils.get_current_buffer()
  if not buffer then
    return
  end

  local comment = buffer:get_comment_at_cursor()
  if not comment then
    utils.error "The cursor does not seem to be located at any comment"
    return
  end
  local start_line = comment.bufferStartLine
  local end_line = comment.bufferEndLine

  local query, threadId
  if comment.kind == "IssueComment" then
    query = graphql("delete_issue_comment_mutation", comment.id)
  elseif comment.kind == "PullRequestReviewComment" then
    query = graphql("delete_pull_request_review_comment_mutation", comment.id)
    local _thread = buffer:get_thread_at_cursor()
    threadId = _thread.threadId
  elseif comment.kind == "DiscussionComment" then
    query = graphql("delete_discussion_comment_mutation", comment.id)
  elseif comment.kind == "PullRequestReview" then
    -- Review top level comments cannot be deleted here
    return
  end

  local choice = vim.fn.confirm("Delete comment?", "&Yes\n&No\n&Cancel", 2)
  if choice == 1 then
    gh.run {
      args = { "api", "graphql", "-f", string.format("query=%s", query) },
      cb = function(output)
        -- TODO: deleting the last review thread comment, it deletes the whole thread and review
        -- In issue buffers, we should hide the thread snippet
        local resp = vim.json.decode(output)

        -- remove comment lines from the buffer
        if comment.reactionLine then
          vim.api.nvim_buf_set_lines(buffer.bufnr, start_line - 2, end_line + 1, false, {})
          vim.api.nvim_buf_clear_namespace(buffer.bufnr, constants.OCTO_REACTIONS_VT_NS, start_line - 2, end_line + 1)
        else
          vim.api.nvim_buf_set_lines(buffer.bufnr, start_line - 2, end_line - 1, false, {})
        end
        vim.api.nvim_buf_clear_namespace(buffer.bufnr, comment.namespace, 0, -1)
        vim.api.nvim_buf_del_extmark(buffer.bufnr, constants.OCTO_COMMENT_NS, comment.extmark)
        local comments = buffer.commentsMetadata
        if comments then
          local updated = {}
          for _, c in ipairs(comments) do
            if c.id ~= comment.id then
              table.insert(updated, c)
            end
          end
          buffer.commentsMetadata = updated
        end

        if comment.kind == "PullRequestReviewComment" then
          local review = reviews.get_current_review()
          if not review then
            utils.error "Cannot find review for this comment"
            return
          end

          local threads = resp.data.deletePullRequestReviewComment.pullRequestReview.pullRequest.reviewThreads.nodes

          -- check if there is still at least a PENDING comment
          local review_was_deleted = true
          for _, thread in ipairs(threads) do
            for _, c in ipairs(thread.comments.nodes) do
              if c.state == "PENDING" then
                review_was_deleted = false
                break
              end
            end
          end
          if review_was_deleted then
            -- we deleted the last pending comment and therefore GitHub closed the review, create a new one
            review:create(function(resp)
              review.id = resp.data.addPullRequestReview.pullRequestReview.id
              local updated_threads = resp.data.addPullRequestReview.pullRequestReview.pullRequest.reviewThreads.nodes
              review:update_threads(updated_threads)
            end)
          else
            review:update_threads(threads)
          end

          -- check if we removed the last comment of a thread
          local thread_was_deleted = true
          for _, thread in ipairs(threads) do
            if threadId == thread.id then
              thread_was_deleted = false
              break
            end
          end
          if thread_was_deleted then
            -- this was the last comment, close the thread buffer
            -- No comments left
            utils.error("Deleting buffer " .. tostring(buffer.bufnr))
            local bufname = vim.api.nvim_buf_get_name(buffer.bufnr)
            local split = string.match(bufname, "octo://.+/review/[^/]+/threads/([^/]+)/.*")
            if split then
              local layout = reviews.get_current_review().layout
              local file = layout:get_current_file()
              if not file then
                return
              end
              local thread_win = file:get_alternative_win(split)
              local original_buf = file:get_alternative_buf(split)
              -- move focus to the split containing the diff buffer
              -- restore the diff buffer so that window is not closed when deleting thread buffer
              vim.api.nvim_win_set_buf(thread_win, original_buf)
              -- delete the thread buffer
              pcall(vim.api.nvim_buf_delete, buffer.bufnr, { force = true })
              -- refresh signs and virtual text
              file:place_signs()
              -- diff buffers
              file:show_diff()
            end
          end
        end
      end,
    }
  end
end

local function update_review_thread_header(bufnr, thread, thread_id, thread_line)
  local start_line = thread.originalStartLine ~= vim.NIL and thread.originalStartLine or thread.originalLine
  local end_line = thread.originalLine
  local commit_id = ""
  for _, review_threads in ipairs(thread.pullRequest.reviewThreads.nodes) do
    if review_threads.id == thread_id then
      commit_id = review_threads.comments.nodes[1].originalCommit.abbreviatedOid
    end
  end
  writers.write_review_thread_header(bufnr, {
    path = thread.path,
    start_line = start_line,
    end_line = end_line,
    commit = commit_id,
    isOutdated = thread.isOutdated,
    isResolved = thread.isResolved,
  }, thread_line - 2)
  local threads = thread.pullRequest.reviewThreads.nodes
  local review = reviews.get_current_review()
  if review then
    review:update_threads(threads)
  end
end

function M.resolve_thread()
  local buffer = utils.get_current_buffer()

  if not buffer then
    return
  end

  local _thread = buffer:get_thread_at_cursor()
  if not _thread then
    return
  end
  local thread_id = _thread.threadId
  local thread_line = _thread.bufferStartLine
  local query = graphql("resolve_review_thread_mutation", thread_id)
  gh.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
      elseif output then
        local resp = vim.json.decode(output)
        local thread = resp.data.resolveReviewThread.thread
        if thread.isResolved then
          update_review_thread_header(buffer.bufnr, thread, thread_id, thread_line)
          --vim.cmd(string.format("%d,%dfoldclose", thread_line, thread_line))
        end
      end
    end,
  }
end

function M.unresolve_thread()
  local buffer = utils.get_current_buffer()

  if not buffer then
    return
  end
  local _thread = buffer:get_thread_at_cursor()
  if not _thread then
    return
  end
  local thread_id = _thread.threadId
  local thread_line = _thread.bufferStartLine
  local query = graphql("unresolve_review_thread_mutation", thread_id)
  gh.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
      elseif output then
        local resp = vim.json.decode(output)
        local thread = resp.data.unresolveReviewThread.thread
        if not thread.isResolved then
          update_review_thread_header(buffer.bufnr, thread, thread_id, thread_line)
        end
      end
    end,
  }
end

---@param state "OPEN"|"CLOSED"
function M.change_state(state)
  local buffer = utils.get_current_buffer()

  if not buffer then
    return
  end

  if not state then
    utils.error "Missing argument: state"
    return
  end

  local node = buffer:isIssue() and buffer:issue() or buffer:pullRequest()
  local id = node.id
  local query, jq, desired_state, fields
  if buffer:isIssue() and state == "CLOSED" then
    query = mutations.update_issue_state
    desired_state = state
    jq = ".data.updateIssue.issue"
    fields = { id = id, state = state }
  elseif buffer:isIssue() and state == "OPEN" then
    query = mutations.reopen_issue
    desired_state = "OPEN"
    jq = ".data.reopenIssue.issue"
    fields = { issueId = id }
  elseif buffer:isIssue() then
    query = mutations.close_issue
    desired_state = "CLOSED"
    jq = ".data.closeIssue.issue"
    fields = { issueId = id, stateReason = state }
  elseif buffer:isPullRequest() then
    query = mutations.update_pull_request_state
    desired_state = state
    jq = ".data.updatePullRequest.pullRequest"
    fields = { pullRequestId = id, state = state }
  end

  local function update_state(output)
    local obj = vim.json.decode(output)
    local new_state = obj.state

    if desired_state ~= new_state then
      return
    end

    node.state = new_state

    local updated_state = utils.get_displayed_state(buffer:isIssue(), new_state, obj.stateReason)
    writers.write_state(buffer.bufnr, updated_state:upper(), buffer.number)
    writers.write_details(buffer.bufnr, obj, true)
    local kind = buffer:isIssue() and "Issue" or "Pull Request"
    utils.info(kind .. " state changed to: " .. updated_state)
  end

  gh.api.graphql {
    query = query,
    jq = jq,
    fields = fields,
    opts = {
      cb = gh.create_callback { success = update_state },
    },
  }
end

function M.create_issue(repo)
  local buffer = utils.get_current_buffer()
  if not repo then
    repo = buffer.repo or utils.get_remote_name()
  end

  if not repo then
    utils.error "Cant find repo name"
    return
  end

  local templates = utils.get_repo_templates(repo)
  if not utils.is_blank(templates) and #templates.issueTemplates > 0 then
    require("octo.picker").issue_templates(templates.issueTemplates, function(selected)
      M.save_issue {
        repo = repo,
        base_title = selected.title,
        base_body = selected.body,
      }
    end)
  else
    M.save_issue {
      repo = repo,
      base_title = "",
      base_body = "",
    }
  end
end

---@class SaveIssueOpts
---@field repo string
---@field base_title string
---@field base_body? string

---@param opts SaveIssueOpts
function M.save_issue(opts)
  vim.fn.inputsave()
  local title = vim.fn.input(string.format("Creating issue in %s. Enter title: ", opts.repo), opts.base_title)
  vim.fn.inputrestore()

  local body
  if utils.is_blank(opts.base_body) then
    local choice = vim.fn.confirm(
      "Do you want to use the content of the current buffer as the body for the new issue?",
      "&Yes\n&No\n&Cancel",
      2
    )
    if choice == 1 then
      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, true)
      body = utils.escape_char(utils.trim(table.concat(lines, "\n")))
    else
      body = constants.NO_BODY_MSG
    end
  else
    body = utils.escape_char(opts.base_body)
    -- TODO: let the user edit the template before submitting
  end

  gh.api.graphql {
    query = mutations.create_issue,
    jq = ".data.createIssue.issue",
    F = { input = { repositoryId = utils.get_repo_id(opts.repo), title = title, body = body } },
    opts = {
      cb = gh.create_callback {
        success = function(output)
          require("octo").create_buffer("issue", vim.json.decode(output), opts.repo, true)
          vim.fn.execute "normal! Gk"
          vim.fn.execute "startinsert"
        end,
      },
    },
  }
end

function M.create_pr(is_draft)
  is_draft = "draft" == is_draft and true or false
  local conf = config.values
  local select = conf.pull_requests.always_select_remote_on_create or false

  local repo
  if select then
    local remotes = utils.get_all_remotes()
    local remote_entries = { "Select base repo," }
    for idx, remote in ipairs(remotes) do
      table.insert(remote_entries, idx .. ". " .. remote.repo)
    end
    local remote_idx = vim.fn.inputlist(remote_entries)
    if remote_idx < 1 then
      utils.error "Aborting PR creation"
      return
    elseif remote_idx > #remotes then
      utils.error "Invalid index."
      return
    end
    repo = remotes[remote_idx].repo
  else
    -- Override the precedence of get_remote, because otherwise upstream is selected
    -- and the check if the local branch creates on the repo fails.
    repo = utils.get_remote_name { "origin" }
    if not repo then
      repo = utils.get_remote_name()
    end
    if not repo then
      utils.error "Cant find repo name"
      return
    end
  end

  -- get repo info
  local info = utils.get_repo_info(repo)

  -- repo candidates = self + parent (in case of fork)
  local repo_candidates_entries = { "Select target repo", "1. " .. repo }
  local repo_candidates = { repo }
  if info.isFork then
    table.insert(repo_candidates_entries, "2. " .. info.parent.nameWithOwner)
    table.insert(repo_candidates, info.parent.nameWithOwner)
  end

  -- get current local branch
  local cmd = "git rev-parse --abbrev-ref HEAD"
  local local_branch = string.gsub(vim.fn.system(cmd), "%s+", "")

  -- get remote branches
  if
    info == nil
    or info.refs == nil
    or info.refs.nodes == nil
    or info == vim.NIL
    or info.refs == vim.NIL
    or info.refs.nodes == vim.NIL
  then
    utils.error "Cannot grab remote branches"
    return
  end
  local remote_branches = info.refs.nodes

  local remote_branch_exists = false
  for _, remote_branch in ipairs(remote_branches) do
    if local_branch == remote_branch.name then
      remote_branch_exists = true
    end
  end
  local remote_branch = local_branch
  if not remote_branch_exists then
    local choice =
      vim.fn.confirm("Remote branch '" .. local_branch .. "' does not exist. Push local one?", "&Yes\n&No\n&Cancel", 2)
    if choice == 1 then
      local remote = "origin"
      remote_branch = vim.fn.input {
        prompt = "Enter remote branch name: ",
        default = local_branch,
        highlight = function(input)
          return { { 0, #input, "String" } }
        end,
      }
      utils.info(string.format("Pushing '%s' to '%s:%s' ...", local_branch, remote, remote_branch))
      local ok, Job = pcall(require, "plenary.job")
      if ok then
        local job = Job:new {
          command = "git",
          args = { "push", remote, local_branch .. ":" .. remote_branch },
          cwd = vim.fn.getcwd(),
        }
        job:sync()
        --local stdout = table.concat(job:result(), "\n")
        local stderr = table.concat(job:stderr_result(), "\n")
        if not utils.is_blank(stderr) then
          utils.error(stderr)
        end
      else
        utils.error "Aborting PR creation"
        return
      end
    else
      utils.error "Aborting PR creation"
      return
    end
  end

  local templates = utils.get_repo_templates(repo)
  local base_body = ""
  if not utils.is_blank(templates) and #templates.pullRequestTemplates > 0 then
    base_body = templates.pullRequestTemplates[1].body
  end
  M.save_pr {
    repo = repo,
    base_title = "",
    base_body = base_body,
    candidates = repo_candidates,
    candidate_entries = repo_candidates_entries,
    is_draft = is_draft,
    info = info,
    remote_branch = remote_branch,
  }
end

function M.save_pr(opts)
  vim.fn.inputsave()
  local repo_idx = 1
  if #opts.candidates > 1 then
    repo_idx = vim.fn.inputlist(opts.candidate_entries)
  end

  local conf = config.values
  local use_branch_name_as_title = conf.pull_requests.use_branch_name_as_title or false
  -- title and body
  local title, body
  local last_commit = string.gsub(vim.fn.system "git log -1 --pretty=%B", "%s+$", "")
  local last_commit_lines = vim.split(last_commit, "\n")
  if #last_commit_lines >= 1 then
    title = last_commit_lines[1]
  end
  if use_branch_name_as_title then
    title = opts.remote_branch
  end
  if #last_commit_lines > 1 then
    if utils.is_blank(last_commit_lines[2]) and #last_commit_lines > 2 then
      body = table.concat(vim.list_slice(last_commit_lines, 3, #last_commit_lines), "\n")
    else
      body = table.concat(vim.list_slice(last_commit_lines, 2, #last_commit_lines), "\n")
    end
  end
  if not utils.is_blank(opts.base_body) then
    body = opts.base_body
    --TODO: append last commit?
    -- TODO: let the use edit the body
  end

  -- title
  title = vim.fn.input {
    prompt = "Enter title: ",
    default = title,
    highlight = function(input)
      return { { 0, #input, "String" } }
    end,
  }

  -- The name of the branch you want your changes pulled into. This should be an existing branch on the current repository.
  -- You cannot update the base branch on a pull request to point to another repository.
  -- get repo default branch
  local default_branch = opts.info.defaultBranchRef.name
  local base_ref_name = vim.fn.input {
    prompt = "Enter BASE branch: ",
    default = default_branch,
    highlight = function(input)
      return { { 0, #input, "String" } }
    end,
  }
  -- The name of the branch where your changes are implemented. For cross-repository pull requests in the same network,
  -- namespace head_ref_name with a user like this: username:branch.
  local head_ref_name = vim.fn.input {
    prompt = "Enter HEAD branch: ",
    default = opts.remote_branch,
    highlight = function(input)
      return { { 0, #input, "String" } }
    end,
  }
  if opts.info.isFork and opts.candidates[repo_idx] == opts.info.parent.nameWithOwner then
    head_ref_name = vim.g.octo_viewer .. ":" .. head_ref_name
  end
  vim.fn.inputrestore()

  local repo_id = utils.get_repo_id(opts.candidates[repo_idx])
  local choice = vim.fn.confirm("Create PR?", "&Yes\n&No\n&Cancel", 2)
  if choice == 1 then
    gh.api.graphql {
      query = mutations.create_pr,
      F = {
        input = {
          repositoryId = repo_id,
          baseRefName = base_ref_name,
          headRefName = head_ref_name,
          title = title and title or "",
          body = body and body or "",
          draft = opts.is_draft,
        },
      },
      jq = ".data.createPullRequest.pullRequest",
      opts = {
        cb = gh.create_callback {
          success = function(output)
            local pr = vim.json.decode(output)
            utils.info(string.format("#%d - `%s` created successfully", pr.number, pr.title))
            require("octo").create_buffer("pull", pr, opts.repo, true)
          end,
        },
      },
    }
  end
end

--- @class PRReadyOpts
--- @field pr octo.PullRequest The PR
--- @field bufnr integer Buffer number
--- @field undo boolean Whether to undo from ready to draft

--- Change PR state to ready for review or draft
--- @param opts PRReadyOpts
function M.gh_pr_ready(opts)
  gh.pr.ready {
    opts.pr.number,
    repo = opts.pr.baseRepository.nameWithOwner,
    undo = opts.undo,
    opts = {
      cb = gh.create_callback {
        -- There seems to be something wrong with the CLI output. It comes back as stderr
        failure = function(output)
          utils.info(output)
          writers.write_state(opts.bufnr)
        end,
        success = utils.error,
      },
    },
  }
end

local parse_checks = function(data)
  local checks = {}
  for _, row in ipairs(data) do
    checks[#checks + 1] = {
      row.name,
      row.bucket,
      row.seconds ~= nil and utils.format_seconds(row.seconds) or "",
      row.link,
    }
  end
  return checks
end

local get_max_lengths = function(data)
  local max_lengths = {}
  if #data == 0 then
    return max_lengths
  end

  -- Initialize max_lengths with zeros for each column
  for col = 1, #data[1] do
    max_lengths[col] = 0
  end

  for _, row in ipairs(data) do
    for col, word in ipairs(row) do
      local word_length = #word
      if word_length > max_lengths[col] then
        max_lengths[col] = word_length
      end
    end
  end
  return max_lengths
end

local format_checks = function(parts)
  local max_lengths = get_max_lengths(parts)

  local lines = {}
  for _, p in pairs(parts) do
    local line = {}
    for i, pp in pairs(p) do
      table.insert(line, pp .. (" "):rep(max_lengths[i] - #pp))
    end
    table.insert(lines, table.concat(line, "  "))
  end
  return lines
end

---@param buffer OctoBuffer
function M.pr_checks(buffer)
  local mappings = require("octo.config").values.mappings.runs

  local function show_checks(data)
    data = vim.json.decode(data)

    for _, row in ipairs(data) do
      if row.bucket == "pending" or row.bucket == "skipped" or row.completedAt == "0001-01-01T00:00:00Z" then
        row.seconds = nil
      else
        row.seconds = utils.seconds_between(row.startedAt, row.completedAt)
      end

      row.name = string.gsub(row.name, "\n", " ")
    end

    local parts = parse_checks(data)
    local lines = format_checks(parts)
    local _, wbufnr = window.create_centered_float {
      header = "Checks",
      content = lines,
    }

    vim.api.nvim_buf_set_keymap(wbufnr, "n", "<CR>", "", {
      noremap = true,
      silent = true,
      callback = function()
        local line_number = vim.api.nvim_win_get_cursor(0)[1]
        local url = data[line_number].link
        local run_id = string.match(url, "runs/(%d+)")

        if not run_id then
          utils.error(
            "Cannot find workflow run id. Consider opening in the browser with " .. mappings.open_in_browser.lhs
          )
          return
        end

        local workflow = require "octo.workflow_runs"
        workflow.render { id = run_id }
      end,
    })

    vim.api.nvim_buf_set_keymap(wbufnr, "n", mappings.open_in_browser.lhs, "", {
      noremap = true,
      silent = true,
      callback = function()
        local line_number = vim.api.nvim_win_get_cursor(0)[1]
        local url = data[line_number].link
        navigation.open_in_browser_raw(url)
      end,
    })

    vim.api.nvim_buf_set_keymap(wbufnr, "n", mappings.rerun.lhs, "", {
      noremap = true,
      silent = true,
      callback = function()
        local line_number = vim.api.nvim_win_get_cursor(0)[1]
        local url = data[line_number].link
        local job_id = string.match(url, "job/(%d+)$")
        if not job_id then
          utils.error "Cannot find check run id"
          return
        end
        gh.run.rerun {
          job = job_id,
          opts = {
            cb = gh.create_callback {
              success = function()
                utils.info("Rerunning job for " .. data[line_number].name)
              end,
            },
          },
        }
      end,
    })

    for i, l in ipairs(data) do
      local color_line = function(color)
        vim.api.nvim_buf_add_highlight(wbufnr, -1, color, i - 1, 0, -1)
      end

      if l.bucket == "pass" then
        color_line "OctoPassingTest"
      elseif l.bucket == "fail" then
        color_line "OctoFailingTest"
      elseif l.bucket == "pending" then
        color_line "OctoPendingTest"
      end
    end

    vim.bo[wbufnr].modifiable = false
  end

  gh.pr.checks {
    buffer.number,
    repo = buffer.repo,
    json = "name,bucket,startedAt,completedAt,link",
    opts = {
      cb = gh.create_callback {
        success = show_checks,
      },
    },
  }
end

function M.merge_pr(...)
  local buffer = utils.get_current_buffer()
  if not buffer or not buffer:isPullRequest() then
    return
  end

  local node = buffer:pullRequest()

  local opts = {
    buffer.number,
    repo = node.baseRepository.nameWithOwner,
  }

  local params = table.pack(...)
  local conf = config.values

  local merge_method = conf.default_merge_method
  for _, param in ipairs(params) do
    if utils.merge_method_to_flag[param] then
      merge_method = param
      break
    end
  end
  opts[merge_method] = true

  local delete_branch = conf.default_delete_branch
  for _, param in ipairs(params) do
    if param == "delete" then
      delete_branch = true
    end
    if param == "nodelete" then
      delete_branch = false
    end
  end
  opts["delete-branch"] = delete_branch

  for _, param in ipairs(params) do
    if utils.merge_queue_to_flag[param] then
      opts["auto"] = true
    end
  end

  opts.opts = {
    cb = function(output, stderr, exit_code)
      local log = exit_code == 0 and utils.info or utils.error
      log(output .. " " .. stderr)
      writers.write_state(buffer.bufnr)
    end,
  }

  gh.pr.merge(opts)
end

function M.show_pr_diff()
  local buffer = utils.get_current_buffer()
  if not buffer or not buffer:isPullRequest() then
    return
  end

  local url = string.format("/repos/%s/pulls/%s", buffer.repo, buffer.number)
  gh.run {
    args = { "api", "--paginate", url },
    headers = { headers.diff },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
      elseif output then
        local lines = vim.split(output, "\n")
        local wbufnr = vim.api.nvim_create_buf(true, true)
        vim.api.nvim_buf_set_lines(wbufnr, 0, -1, false, lines)
        vim.api.nvim_set_current_buf(wbufnr)
        vim.api.nvim_buf_set_option(wbufnr, "filetype", "diff")
      end
    end,
  }
end

local function get_reaction_line(bufnr, extmark)
  local prev_extmark = extmark
  local mark = vim.api.nvim_buf_get_extmark_by_id(bufnr, constants.OCTO_COMMENT_NS, prev_extmark, { details = true })
  local _, end_line = utils.get_extmark_region(bufnr, mark)
  return end_line + 3
end

local function get_reaction_info(bufnr, buffer)
  local reaction_groups, reaction_line, insert_line, id
  local comment = buffer:get_comment_at_cursor()
  if comment then
    -- found a comment at cursor
    id = comment.id
    reaction_groups = comment.reactionGroups
    reaction_line = get_reaction_line(bufnr, comment.extmark)
    if not comment.reactionLine then
      insert_line = true
    end
  elseif buffer:isIssue() or buffer:isPullRequest() or buffer:isDiscussion() then
    -- using the issue body instead
    id = buffer.node.id
    reaction_groups = buffer.bodyMetadata.reactionGroups
    reaction_line = get_reaction_line(bufnr, buffer.bodyMetadata.extmark)
    if not buffer.bodyMetadata.reactionLine then
      insert_line = true
    end
  end
  return reaction_line, reaction_groups, insert_line, id
end

function M.mark(opts)
  opts = opts or {}

  local buffer = utils.get_current_buffer()
  if not buffer or not buffer:isDiscussion() then
    utils.error "Not a discussion buffer"
    return
  end

  local comment = buffer:get_comment_at_cursor()

  if not comment then
    return
  end

  gh.api.graphql {
    query = opts.undo and mutations.unmark_answer or mutations.mark_answer,
    f = { id = comment.id },
    opts = {
      cb = gh.create_callback {
        success = function(_)
          -- TODO: Update the buffer to reflect the changes
          local msg = opts.undo and "unmarked" or "marked"
          utils.info("Comment " .. msg)
        end,
      },
    },
  }
end

function M.reaction_action(reaction)
  local buffer = utils.get_current_buffer()
  if not buffer then
    return
  end

  -- normalize reactions
  reaction = reaction:upper()
  if reaction == "+1" then
    reaction = "THUMBS_UP"
  elseif reaction == "-1" then
    reaction = "THUMBS_DOWN"
  elseif reaction == "PARTY" or reaction == "TADA" then
    reaction = "HOORAY"
  end

  local reaction_line, reaction_groups, insert_line, id = get_reaction_info(buffer.bufnr, buffer)

  local action
  for _, reaction_group in ipairs(reaction_groups) do
    if reaction_group.content == reaction and reaction_group.viewerHasReacted then
      action = "remove"
      break
    elseif reaction_group.content == reaction and not reaction_group.viewerHasReacted then
      action = "add"
      break
    end
  end
  if action ~= "add" and action ~= "remove" then
    return
  end

  -- add/delete reaction
  local query = graphql(action .. "_reaction_mutation", id, reaction)
  gh.run {
    args = { "api", "graphql", "-f", string.format("query=%s", query) },
    cb = function(output, stderr)
      if stderr and not utils.is_blank(stderr) then
        utils.error(stderr)
      elseif output then
        local resp = vim.json.decode(output)
        if action == "add" then
          reaction_groups = resp.data.addReaction.subject.reactionGroups
        elseif action == "remove" then
          reaction_groups = resp.data.removeReaction.subject.reactionGroups
        end

        buffer:update_reactions_at_cursor(reaction_groups, reaction_line)
        if action == "remove" and utils.count_reactions(reaction_groups) == 0 then
          -- delete lines
          vim.api.nvim_buf_set_lines(buffer.bufnr, reaction_line - 1, reaction_line + 1, false, {})
          vim.api.nvim_buf_clear_namespace(
            buffer.bufnr,
            constants.OCTO_REACTIONS_VT_NS,
            reaction_line - 1,
            reaction_line + 1
          )
        elseif action == "add" and insert_line then
          -- add lines
          vim.api.nvim_buf_set_lines(buffer.bufnr, reaction_line - 1, reaction_line - 1, false, { "", "" })
        end
        writers.write_reactions(buffer.bufnr, reaction_groups, reaction_line)
        buffer:update_metadata()
      end
    end,
  }
end

function M.set_project_v2_card()
  local buffer = utils.get_current_buffer()
  if not buffer then
    return
  end

  -- show column selection picker
  picker.project_columns_v2(function(project_id, field_id, value)
    local node = buffer:isIssue() and buffer:issue() or buffer:pullRequest()
    -- add new card
    local add_query = graphql("add_project_v2_item_mutation", node.id, project_id)
    gh.run {
      args = { "api", "graphql", "--paginate", "-f", string.format("query=%s", add_query) },
      cb = function(add_output, add_stderr)
        if add_stderr and not utils.is_blank(add_stderr) then
          utils.error(add_stderr)
        elseif add_output then
          local resp = vim.json.decode(add_output)
          local update_query = graphql(
            "update_project_v2_item_mutation",
            project_id,
            resp.data.addProjectV2ItemById.item.id,
            field_id,
            value
          )
          gh.run {
            args = { "api", "graphql", "--paginate", "-f", string.format("query=%s", update_query) },
            cb = function(update_output, update_stderr)
              if update_stderr and not utils.is_blank(update_stderr) then
                utils.error(update_stderr)
              elseif update_output then
                -- TODO do update here
                -- refresh issue/pr details
                require("octo").load(buffer.repo, buffer.kind, buffer.number, function(obj)
                  writers.write_details(buffer.bufnr, obj, true)
                  node.projectCards = obj.projectCards
                end)
              end
            end,
          }
        end
      end,
    }
  end)
end

function M.remove_project_v2_card()
  local buffer = utils.get_current_buffer()
  if not buffer then
    return
  end

  -- show card selection picker
  picker.project_cards_v2(function(project_id, item_id)
    local node = buffer:isIssue() and buffer:issue() or buffer:pullRequest()
    -- delete card
    local query = graphql("delete_project_v2_item_mutation", project_id, item_id)
    gh.run {
      args = { "api", "graphql", "--paginate", "-f", string.format("query=%s", query) },
      cb = function(output, stderr)
        if stderr and not utils.is_blank(stderr) then
          utils.error(stderr)
        elseif output then
          -- refresh issue/pr details
          require("octo").load(buffer.repo, buffer.kind, buffer.number, function(obj)
            node.projectCards = obj.projectCards
            writers.write_details(buffer.bufnr, obj, true)
          end)
        end
      end,
    }
  end)
end

function M.reload(opts)
  require("octo").load_buffer(opts)
end

function M.random_hex_color()
  local chars = { "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "B", "C", "D", "E", "F" }
  math.randomseed(os.time())
  local color = {}
  for _ = 1, 6 do
    table.insert(color, chars[math.random(1, 16)])
  end
  return table.concat(color, "")
end

function M.create_label(label)
  local repo = utils.get_remote_name()
  if repo == nil then
    utils.error "Cannot find repo name"
    return
  end

  local repo_id = utils.get_repo_id(repo)

  local name, color, description
  if label then
    name = label
    color = M.random_hex_color()
    description = ""
  else
    vim.fn.inputsave()
    name = vim.fn.input(string.format("Creating label for %s. Enter title: ", repo))
    color = vim.fn.input "Enter color (RGB): "
    description = vim.fn.input "Enter description: "
    vim.fn.inputrestore()
    if color == "" then
      color = M.random_hex_color()
    end
    color = string.gsub(color, "#", "")
  end

  local query = graphql("create_label_mutation", repo_id, name, description, color)
  gh.api.graphql {
    query = query,
    jq = ".data.createLabel.label.name",
    opts = {
      cb = gh.create_callback {
        success = function(label_name)
          utils.info("Created label: " .. label_name)
        end,
      },
    },
  }
end

local function format(str)
  return string.format('"%s"', str)
end

local function create_list(values, fmt)
  if type(values) == "string" then
    return fmt(values)
  end

  local formatted_values = {}
  for _, value in ipairs(values) do
    table.insert(formatted_values, fmt(value))
  end
  return "[" .. table.concat(formatted_values, ", ") .. "]"
end

local function label_action(opts)
  local label = opts.label

  local buffer = utils.get_current_buffer()
  if not buffer then
    return
  end

  local iid = buffer.node.id
  if not iid then
    utils.error "Cannot get issue/pr/discussion id"
  end

  local function cb(labels)
    local label_ids = {}
    for _, lbl in ipairs(labels) do
      table.insert(label_ids, lbl.id)
    end

    local function refresh_details()
      require("octo").load(buffer.repo, buffer.kind, buffer.number, function(obj)
        if buffer:isDiscussion() then
          writers.write_discussion_details(buffer.bufnr, obj)
        else
          writers.write_details(buffer.bufnr, obj, true)
        end
      end)
    end

    local query = graphql(opts.query_name, iid, create_list(label_ids, format))
    gh.api.graphql {
      query = query,
      opts = {
        cb = gh.create_callback {
          success = refresh_details,
        },
      },
    }
  end

  if label then
    local label_id = utils.get_label_id(label)
    if label_id then
      cb { { id = label_id } }
    else
      utils.error("Cannot find label: " .. label)
    end
  else
    opts.labels {
      repo = buffer.owner .. "/" .. buffer.name,
      cb = cb,
    }
  end
end

function M.add_label(label)
  return label_action {
    query_name = "add_labels_mutation",
    label = label,
    labels = picker.labels,
  }
end

function M.remove_label(label)
  return label_action {
    query_name = "remove_labels_mutation",
    label = label,
    labels = picker.assigned_labels,
  }
end

---@param subject "assignee"|"reviewer"
---@param logins? string[]
function M.add_user(subject, logins)
  local buffer = utils.get_current_buffer()
  if not buffer then
    utils.error "No Octo buffer"
    return
  end

  local iid = buffer.node.id
  if not iid then
    utils.error "Cannot get issue/pr id"
  end

  ---@param user_ids string[]
  local function cb(user_ids)
    local query ---@type string
    if subject == "assignee" then
      query = mutations.add_assignees
    elseif subject == "reviewer" then
      query = mutations.request_reviews
    else
      utils.error "Invalid user type"
      return
    end
    gh.api.graphql {
      paginate = true,
      query = query,
      F = {
        user_ids = user_ids,
        object_id = iid,
      },
      opts = {
        cb = gh.create_callback {
          success = function()
            -- refresh issue/pr details
            require("octo").load(buffer.repo, buffer.kind, buffer.number, function(obj)
              writers.write_details(buffer.bufnr, obj, true)
              vim.cmd [[stopinsert]]
            end)
          end,
        },
      },
    }
  end
  if logins then
    local user_ids = {} ---@type string[]
    for _, user in ipairs(logins) do
      local user_id = utils.get_user_id(user)
      if user_id then
        user_ids[#user_ids + 1] = user_id
      else
        utils.error("User " .. user .. " not found")
        return
      end
    end
    cb(user_ids)
  else
    picker.users(function(user_id)
      cb { user_id }
    end)
  end
end

function M.remove_user(subject, login)
  if subject == "assignee" then
    M.remove_assignee(login)
  elseif subject == "reviewer" then
    M.remove_reviewer(login)
  else
    utils.error("Remove user not implemented for: " .. subject)
  end
end

function M.remove_assignee(login)
  local buffer = utils.get_current_buffer()
  if not buffer then
    return
  end

  local iid = buffer.node.id
  if not iid then
    utils.error "Cannot get issue/pr id"
  end

  local function cb(user_id)
    local query = graphql("remove_assignees_mutation", iid, user_id)
    gh.run {
      args = { "api", "graphql", "--paginate", "-f", string.format("query=%s", query) },
      cb = function(output, stderr)
        if stderr and not utils.is_blank(stderr) then
          utils.error(stderr)
        elseif output then
          -- refresh issue/pr details
          require("octo").load(buffer.repo, buffer.kind, buffer.number, function(obj)
            writers.write_details(buffer.bufnr, obj, true)
          end)
        end
      end,
    }
  end
  if login then
    local user_id = utils.get_user_id(login)
    if user_id then
      cb(user_id)
    else
      utils.error "User not found"
    end
  else
    picker.assignees(cb)
  end
end

function M.remove_reviewer(login)
  local buffer = utils.get_current_buffer()
  if not buffer then
    utils.error "No buffer found"
    return
  end

  if not buffer:isPullRequest() then
    utils.error "Not a pull request buffer"
    return
  end

  local function cb(reviewer_login)
    gh.pr.edit {
      buffer.number,
      remove_reviewer = reviewer_login,
      opts = {
        cb = gh.create_callback {
          success = function()
            require("octo").load(buffer.repo, buffer.kind, buffer.number, function(obj)
              writers.write_details(buffer.bufnr, obj, true)
            end)
          end,
        },
      },
    }
  end

  if login then
    cb(login)
  else
    -- TODO: Implement reviewer picker when available
    utils.error "Reviewer picker not yet implemented. Please provide a login."
  end
end

function M.copy_url()
  local buffer = utils.get_current_buffer()
  local url

  if buffer then
    url = buffer.node.url
  else
    url = utils.get_remote_url()
  end

  utils.copy_url(url)
end

M.copy_sha = context.within_pr(function(buffer)
  local sha = buffer:pullRequest().headRefOid
  if not sha then
    utils.error "No SHA found"
    return
  end

  utils.copy_sha(sha)
end)

function M.actions()
  local flattened_actions = {}

  for object, commands in pairs(M.commands) do
    if object ~= "actions" then
      if type(commands) == "table" then
        for name, fun in pairs(commands) do
          table.insert(flattened_actions, {
            object = object,
            name = name,
            fun = fun,
          })
        end
      end
    end
  end

  picker.actions(flattened_actions)
end

function M.search(...)
  local args = table.pack(...)
  local prompt = table.concat(args, " ")

  local type = "ISSUE"
  if string.match(prompt, "is:discussion") then
    type = "DISCUSSION"
    prompt = string.gsub(prompt, "is:discussion", "")
  elseif string.match(prompt, "is:repository") then
    type = "REPOSITORY"
    prompt = string.gsub(prompt, "is:repository", "")
  end

  picker.search { prompt = prompt, type = type }
end

--- @class PinIssueOpts
--- @field add boolean Whether to pin or unpin the issue
--- @field obj table The issue object

--- Pin or unpin an issue
--- @param opts PinIssueOpts
function M.pin_issue(opts)
  local query_info = opts.add
      and {
        query = mutations.pin_issue,
        jq = ".data.pinIssue.issue.id",
        error = "pin",
        success = "Pinned",
      }
    or {
      query = mutations.unpin_issue,
      jq = ".data.unpinIssue.issue.id",
      error = "unpin",
      success = "Unpinned",
    }
  gh.api.graphql {
    query = query_info.query,
    F = { issue_id = opts.obj.id },
    jq = query_info.jq,
    opts = {
      cb = gh.create_callback {
        success = function(id)
          if id ~= opts.obj.id then
            utils.error("Failed to " .. query_info.error .. " issue")
            return
          end

          utils.info(query_info.success .. " issue")
        end,
      },
    },
  }
end

return M
