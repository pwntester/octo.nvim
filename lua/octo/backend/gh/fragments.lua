local M = {}

M.projects_v2_fragment = [[
  projectItems(first: 100) {
    nodes {
      id
      project {
        id
        title
      }
      fieldValues(first: 100) {
        nodes {
          ... on ProjectV2ItemFieldSingleSelectValue {
            name
            optionId
            field {
              ... on ProjectV2SingleSelectField {
                name
              }
            }
          }
        }
      }
    }
  }
]]

return M
