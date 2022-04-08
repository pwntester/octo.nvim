local provider = require "octo.pickers.telescope.provider"
return require("telescope").register_extension {
  exports = provider.picker,
}
