local provider = require "octo.telescope.provider"
return require("telescope").register_extension {
  exports = provider.picker
}
