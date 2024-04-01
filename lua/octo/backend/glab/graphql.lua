local M = {}

-- https://docs.gitlab.com/ee/api/graphql/reference/#mergerequest
M.pull_request_query = [[
query {
  mergeRequest(id: "%s") {
    id
    iid
    draft
    title
    description
    state
    author {
      id
      name
      username
    }
    approved
    createdAt
    mergedAt
    updatedAt
    labels {
      nodes {
        title
        color
      }
    }
    diffRefs {
      baseSha
      headSha
      startSha
    }
    diffStatsSummary {
      additions
      changes
      deletions
      fileCount
    }
    diffStats {
      path
    }
    webUrl
    commitCount
    sourceBranch
    targetBranch
    assignees {
      nodes {
        id
        name
        username
      }
    }
    reviewers {
      nodes {
        id
        name
        username
      }
    }
    participants {
      nodes {
        id
        name
        username
      }
    }
  }
}
]]

-- Update informations like description, title
-- https://docs.gitlab.com/ee/api/graphql/reference/#mutationmergerequestupdate
M.merge_request_update_mutation = [[
  mutation {
    mergeRequestUpdate(input: {
      iid: "%d",
      projectPath: "%s",
      title: "%s",
      description: "%s",
    }) {
      errors
      mergeRequest {
        title
        description
      }
    }
  }
]]

M.labels_query = [[
  query {
    group(fullPath: "%s") {
      labels {
        nodes {
          id
          title
          color
        }
      }
    }
  }
]]

-- https://docs.gitlab.com/ee/api/graphql/reference/#mergerequest
M.pull_request_labels_query = [[
  query {
    mergeRequest(id: "%s") {
      labels {
        nodes {
          id
          title
          color
        }
      }
    }
  }
]]

-- https://docs.gitlab.com/ee/api/graphql/reference/#mutationlabelcreate
M.create_label_mutation = [[
  mutation {
    labelCreate(input: {
      projectPath: "%s",
      title: "%s",
      description: "%s",
      color: "#%s",
    }) {
      errors
      label {
        title
      }
    }
  }
]]

-- https://docs.gitlab.com/ee/api/graphql/reference/#mutationmergerequestsetlabels
M.set_labels_mutation = [[
  mutation {
    mergeRequestSetLabels(input: {
      iid: "%d",
      labelIds: ["%s"],
      operationMode: %s,
      projectPath: "%s",
    }) {
      clientMutationId
    }
  }
]]

local function escape_char(string)
  local escaped, _ = string.gsub(string, '["\\]', {
    ['"'] = '\\"',
    ["\\"] = "\\\\",
  })
  return escaped
end

return function(query, ...)
  local opts = { escape = true }
  for _, v in ipairs { ... } do
    if type(v) == "table" then
      opts = vim.tbl_deep_extend("force", opts, v)
      break
    end
  end
  local escaped = {}
  for _, v in ipairs { ... } do
    if type(v) == "string" and opts.escape then
      local encoded = escape_char(v)
      table.insert(escaped, encoded)
    else
      table.insert(escaped, v)
    end
  end
  return string.format(M[query], unpack(escaped))
end
